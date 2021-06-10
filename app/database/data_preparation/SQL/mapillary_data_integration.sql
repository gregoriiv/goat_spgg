--####################################################################################################--
--#################################Mapillary data integration#########################################--
--####################################################################################################--

INSERT INTO pois (origin_geometry, amenity, geom )
SELECT 'point', 'waste_basket', geom 
FROM mapillary_points mp
WHERE mp.value = 'object--trash-can';

INSERT INTO pois (origin_geometry, amenity, geom )
SELECT 'point', 'bench', geom 
FROM mapillary_points mp
WHERE mp.value = 'object--bench';

CREATE OR REPLACE FUNCTION public.meter_degree()
RETURNS NUMERIC AS
$$
	SELECT select_from_variable_container_s('one_meter_degree')::numeric;
$$
LANGUAGE sql IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION array_greatest(anyarray)
RETURNS anyelement
LANGUAGE SQL
AS $$
  SELECT max(elements) FROM unnest($1) elements
$$;

/*This function intersects the footpath table with a polygon table of choice 
and returns the polygon attr and the share of each intersection as arrays. It is expected that there is no overlapping between the polygons. */
DROP FUNCTION IF EXISTS footpaths_get_polygon_attr;
CREATE OR REPLACE FUNCTION footpaths_get_polygon_attr(table_polygon TEXT, polygon_attr TEXT)
RETURNS TABLE(id int8, arr_polygon_attr TEXT[], arr_shares float[])
 LANGUAGE plpgsql
AS $function$
DECLARE
	max_id integer := (SELECT max(f.id) FROM ways f);
	min_border integer := 0;
	max_border integer := 0;
	step integer := 5000;
BEGIN 
	
	WHILE min_border < max_id LOOP 
	
		RAISE NOTICE '% out of % calculated.',min_border, max_id;
	
		max_border = min_border + step;
		
		RETURN query EXECUTE 
		
		'WITH paths AS 
		(
			SELECT f.id, geom 
			FROM ways f
			WHERE f.id >= $1 AND f.id <= $2
		)
		SELECT p.id, j.arr_polygon_attr, j.arr_intersection 
		FROM paths p
		CROSS JOIN LATERAL 
		(
			SELECT ARRAY_AGG(attr) AS arr_polygon_attr, ARRAY_AGG(share_intersection) AS arr_intersection 
			FROM 
			(
				SELECT '|| quote_ident(polygon_attr) ||'::text AS attr, 
				ST_LENGTH(ST_Intersection(ST_UNION(n.geom),p.geom))/ST_LENGTH(p.geom) AS share_intersection
				FROM '|| quote_ident(table_polygon) ||' n
				WHERE ST_INTERSECTS(p.geom, n.geom) 
				GROUP by ' || quote_ident(polygon_attr) || '
			) x
		) j;' USING min_border, max_border;
		
		min_border = min_border + step;
		
	END LOOP;

END; 
$function$;

DROP TABLE IF EXISTS map_lights;
CREATE TABLE map_lights AS
SELECT ST_SUBDIVIDE(ST_UNION(ST_BUFFER(geom, 8*meter_degree())),30) AS geom, 1 AS lit FROM mapillary_points
WHERE value = 'object--street-light';
CREATE INDEX gid ON map_lights USING GIST (geom);
 
WITH lights AS (
				SELECT id, Unnest(arr_polygon_attr) 
				FROM footpaths_get_polygon_attr('map_lights', 'lit')
				WHERE arr_polygon_attr IS NOT NULL
)
UPDATE ways 
SET lit_classified = 'yes'
FROM lights
WHERE ways.id = lights.id;

--####################################################################################################--
--####################################################################################################--


