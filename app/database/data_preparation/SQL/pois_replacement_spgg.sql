--Script updates information about POIs(services) and bus-stops in GOAT
--with data taken from SCIAN(INEGI) - map it acoording GOAT default scheme 
--prepare imported pois_spgg table for import in pois_userinput

ALTER TABLE pois_inegi_spgg
RENAME COLUMN nom_estab TO name;

ALTER TABLE pois_inegi_spgg 
ADD COLUMN amenity TEXT,
ADD COLUMN origin_geometry text;

UPDATE pois_inegi_spgg 
SET origin_geometry = 'point';

-- map amenity values for GOAT according INEGI classification indexes
UPDATE pois_inegi_spgg AS p_s SET
    amenity = c.amenity
FROM (VALUES
    ('611111', 'kindergarten'), ('611112', 'kindergarten'),
    ('611121', 'primary_school'), ('611122', 'primary_school'),
    ('611131', 'secondary_school'), ('611132', 'secondary_school'), ('611141', 'secondary_school'), ('611142', 'secondary_school'),
    ('519121', 'library'), ('519122', 'library'),
    ('722412', 'bar'), 
    ('722515', 'cafe'), 
    ('722514', 'fast_food'), ('722517', 'fast_food'), ('722518', 'fast_food'), ('722519', 'fast_food'), ('722516', 'fast_food'),
    ('722511', 'restaurant'), ('722512', 'restaurant'), ('722513', 'restaurant'),
    ('722411', 'nightclub'),
    ('812110', 'hairdresser'),
    ('621211', 'dentist'), ('621212', 'dentist'),
    ('621111', 'doctors'), ('621112', 'doctors'), ('621115', 'doctors'), ('621116', 'doctors'),
    ('464111', 'pharmacy'), ('464112', 'pharmacy'),
    ('491110', 'post_box'),
    ('468411', 'fuel'),
    ('461190', 'bakery'),
    ('461121', 'butcher'),
    ('463211', 'clothes'),
    ('461110', 'convenience'),
    ('461130', 'greengrocer'),
    ('465313', 'kiosk'),
    ('462210', 'mall'),
    ('463310', 'shoes'),
    ('462111', 'supermarket'),
    ('462112', 'discount_supermarket'),
    ('512130', 'cinema'),
    ('711111', 'theatre'), ('711112', 'theatre'),
    ('712111', 'museum'), ('712112', 'museum'),
    ('721111', 'hotel'), ('721112', 'hotel'), ('721113', 'hotel'),
    ('721190', 'guest_house'),
    ('713113', 'water_park'), ('713114', 'water_park'),
    ('713943', 'gym'), ('713944', 'gym'),
    ('713941', 'sport_club'), ('713942', 'sport_club') --sport club id not presented in GOAT - need to fix
	) AS c(codigo_act, amenity) 
WHERE c.codigo_act = p_s.codigo_act;

--map amenities for banks and atm, for atm name starts with 'CAJERO AUTOM'
UPDATE pois_inegi_spgg 
SET amenity = CASE
				WHEN name LIKE '%CAJERO AUTOM%' THEN 'atm'
				ELSE 'bank'
				END
WHERE codigo_act = '522110';

--change geometry of exported pois to POINT type
ALTER TABLE pois_inegi_spgg 
ALTER COLUMN geom 
SET DATA TYPE geometry;

UPDATE pois_inegi_spgg 
SET geom = ST_GeometryN(geom,1); 


--function for replacement pois with custom pois
CREATE OR REPLACE FUNCTION pois_full_replacement (input_table TEXT, input_amenity TEXT, pois_amenity TEXT )
RETURNS void
LANGUAGE plpgsql
AS $function$
	BEGIN
		DELETE FROM pois_userinput
		WHERE amenity = pois_amenity;

EXECUTE 'INSERT INTO pois_userinput
		SELECT	NULL, pfr.origin_geometry, NULL,NULL, pfr.amenity, NULL, NULL, NULL, NULL, pfr."name", NULL, NULL, NULL, NULL, NULL, NULL, NULL, pfr.geom, NULL
		FROM (SELECT * FROM '||quote_ident(input_table)||' 
		WHERE amenity = '||quote_literal(input_amenity)||') AS pfr';

END;
$function$;

--replace pois from osm to inegi data
WITH amenities AS 
	(SELECT DISTINCT amenity 
	FROM pois_inegi_spgg ps 
	WHERE amenity IS NOT NULL)
SELECT pois_full_replacement('pois_inegi_spgg', amenities.amenity, amenities.amenity) 
FROM amenities;

--prepare bus_stop_spgg table for import in pois_userinput
ALTER TABLE bus_stops_spgg 
ADD COLUMN amenity TEXT,
ADD COLUMN origin_geometry text;

UPDATE bus_stops_spgg 
SET origin_geometry = 'point',
amenity = 'bus_stop';

--replace bus_stops with data from municipality ----need to define different types of buses??
SELECT pois_full_replacement('bus_stops_spgg', 'bus_stop', 'bus_stop');