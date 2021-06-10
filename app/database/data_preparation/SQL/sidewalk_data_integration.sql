--####################################################################################################--
--########################################Sidewalk data integration###################################--
--####################################################################################################--
DROP TABLE IF EXISTS sidewalk;
CREATE TEMP TABLE sidewalk AS
WITH no_side AS ( SELECT geom
 				FROM attributes_sw asw   
 				WHERE asw.label_type = 'NoSidewalk')	
SELECT ns.geom, ways_s.id, ways_s.geom AS way_geom
FROM no_side ns
CROSS JOIN LATERAL
  (SELECT
     id , 
     ways.geom
     FROM ways
     ORDER BY ns.geom <-> ways.geom
   LIMIT 1) AS ways_s;

ALTER TABLE sidewalk
ADD COLUMN deg int4;

UPDATE sidewalk
SET deg = ST_LineCrossingDirection(
						ST_makeLINE(geom, ST_TRANSLATE(ST_CLOSESTPOINT(way_geom, geom), 
						 			sin(ST_AZIMUTH(geom, ST_CLOSESTPOINT(way_geom, geom)))*
										(ST_DISTANCE(ST_CLOSESTPOINT(way_geom, geom), geom)* 1.3),
									cos(ST_AZIMUTH(geom, ST_CLOSESTPOINT(way_geom, geom)))*
										(ST_DISTANCE(ST_CLOSESTPOINT(way_geom, geom), geom)* 1.3))),way_geom
									);
								

UPDATE ways w
SET sidewalk = CASE 
					WHEN (s.deg = -1 AND s.deg = 1) THEN 'no'
					WHEN (s.deg = 1 AND s.deg != -1) THEN 'left'
					WHEN (s.deg = -1 AND s.deg != 1) THEN 'right'
					ELSE ''
				END
FROM sidewalk s 
WHERE s.id = w.id;

UPDATE ways w
SET sidewalk = 'both'
WHERE w.sidewalk IS NULL;

--##########################################################################################################--
--##########################################################################################################--
