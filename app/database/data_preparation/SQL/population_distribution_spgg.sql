--Script creates population for SPGG area table with data fusion from various sources
--Landuse/Cadaster, Geoalert, Census
----------------------------------------------------------------
-- Attach to building population and building height(GeoAlert) data
--create centroids por polygons
ALTER TABLE buildings_from_landuse_spgg 
ADD COLUMN geom_centr geometry;

UPDATE buildings_from_landuse_spgg SET 
	geom_centr = ST_CENTROID(geom);

--add column building height to building table
ALTER TABLE buildings_from_landuse_spgg 
ADD COLUMN building_h NUMERIC;

--add building heights to buildings
UPDATE buildings_from_landuse_spgg AS bfl SET 
	building_h = (SELECT bgs.building_h
					FROM buildings_geoalert_spgg bgs
					WHERE ST_INTERSECTS(bgs.geom, bfl.geom_centr));
				
CREATE OR REPLACE FUNCTION closest_pol(int4)
RETURNS NUMERIC 
AS
$$
DECLARE
  	retVal NUMERIC;
BEGIN
	SELECT bgs.building_h INTO retVal
				FROM buildings_geoalert_spgg bgs, buildings_from_landuse_spgg bfl 
				WHERE ST_INTERSECTS(bgs.geom, ST_BUFFER(bfl.geom_centr, 0.0006,'quad_segs=8')) AND bfl.gid = $1
				ORDER BY ST_INTERSECTION(bgs.geom, ST_BUFFER(bfl.geom_centr, 0.0006,'quad_segs=8')) ASC 
				LIMIT 1;
RETURN retVal;
END;
$$
LANGUAGE plpgsql 
   STABLE 
RETURNS NULL ON NULL INPUT;

--update buildings height for buildings using closest reference to height in Geoalert data radius 50 meters 
UPDATE buildings_from_landuse_spgg AS bfl SET 
	building_h = (SELECT closest_pol(bfl.gid))
	WHERE bfl.building_h IS NULL;

--set default height for buildings with null height value as 6 meters
UPDATE buildings_from_landuse_spgg AS bfl SET 
	building_h = 6
	WHERE bfl.building_h IS NULL;

--create columns building_levels and building_levels_residential
ALTER TABLE buildings_from_landuse_spgg 
ADD COLUMN building_levels NUMERIC,
ADD COLUMN building_levels_residential NUMERIC;

--calculate building levels from buildings heights

UPDATE buildings_from_landuse_spgg 
SET building_levels = FLOOR(building_h/3);

UPDATE buildings_from_landuse_spgg 
SET building_levels_residential = building_levels
WHERE landuse = 'HU' OR landuse = 'HM';

UPDATE buildings_from_landuse_spgg bfls 
SET building_levels_residential =  CASE
									WHEN building_levels = 1  THEN building_levels
									ELSE building_levels - 1
									END
WHERE landuse = 'M1';


--Population calculation for each building
--add column pop in buildings table
ALTER TABLE buildings_from_landuse_spgg 
ADD COLUMN pop float8;


--add population as pop attribute deaggregated from blocks to each building with respect to residential area
UPDATE buildings_from_landuse_spgg AS bfl SET 
	pop = (WITH full_areas AS (
			SELECT cs.gid, cs.geom, cs.pop/sum(ST_AREA(bfl.geom)*bfl.building_levels_residential) AS pop1area
			FROM buildings_from_landuse_spgg bfl, census cs
			WHERE ST_INTERSECTS(cs.geom, bfl.geom_centr)
			GROUP BY cs.gid
			)
		SELECT fa.pop1area*ST_AREA(bfl.geom)*bfl.building_levels_residential
		FROM full_areas fa
		WHERE ST_INTERSECTS(bfl.geom_centr, fa.geom)
		);

--create population table
DROP TABLE IF EXISTS population;
CREATE TABLE population
(gid SERIAL,
population NUMERIC,
geom geometry);

--insert geometry, population data into population table from buildings_from_landuse
INSERT INTO population 
SELECT gid, pop, geom_centr
FROM buildings_from_landuse_spgg bfl;

--export table 'population as shapefile'
---------------------------------------------------------------------------	