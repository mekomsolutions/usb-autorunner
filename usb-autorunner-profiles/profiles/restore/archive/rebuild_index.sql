SELECT 'Set index to be rebuilt on next restart...' as '';
UPDATE global_property
SET    global_property.property_value = ""
WHERE  global_property.property = 'search.indexVersion';
SELECT 'Done.' as '';
