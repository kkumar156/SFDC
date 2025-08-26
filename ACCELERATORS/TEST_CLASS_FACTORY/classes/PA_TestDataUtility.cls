@isTest
public with sharing class PA_TestDataUtility {

    // A map to store default values for specific fields, can be extended.
    private static Map<String, Object> defaultFieldValues = new Map<String, Object>{
        'Name' => 'Test Record',
        'Email' => 'test@example.com',
        'Phone' => '555-123-4567', 
        'Website' => 'http://www.test.com'
    };

    // A set to keep track of objects being processed to prevent infinite recursion in circular lookups.
    private static Set<String> processingObjects = new Set<String>();
    /**
     * Fetches all required fields of an object along with test values for a single record.
     * 
     * @param objectApiName API name of the object.
     * @return SObject with required fields populated with test values.
     */
    public static SObject getRequiredFieldsWithTestValues(String objectApiName) {
        return populateFields(objectApiName, 1, null)[0];
    }
    
    /**
     * Fetches all required fields of an object along with test values for multiple records.
     * 
     * @param objectApiName API name of the object.
     * @param recordCount Number of records to be created.
     * @return List of SObjects with required fields populated with test values.
     */
    public static List<SObject> getRequiredFieldsWithTestValues(String objectApiName, Integer recordCount) {
        return populateFields(objectApiName, recordCount, null);
    }
    
    /**
     * Populates required fields of an object along with test values.
     * 
     * @param objectApiName API name of the object.
     * @return List of SObjects with required fields populated with test values.
     */
    public static List<SObject> populateFields(String objectApiName, Integer recordCount, Map<String, Object> customFieldValues) {
        if (processingObjects.contains(objectApiName)) {
            // Break recursion if we detect a circular dependency
            return new List<SObject>();
        }
        processingObjects.add(objectApiName);
        SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            throw new IllegalArgumentException('Object not found: ' + objectApiName);
        }
        
        List<SObject> records = new List<SObject>();
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        for (Integer i = 0; i < recordCount; i++) {
            SObject obj = objectType.newSObject();
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                if (fieldDescribe.isCreateable() && !fieldDescribe.isDefaultedOnCreate()) {
                    // Check for custom field values first
                    if (customFieldValues != null && customFieldValues.containsKey(fieldName)) {
                        obj.put(fieldName, customFieldValues.get(fieldName));
                        continue;
                    }

                    // Handle required lookup fields
                    if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE && !fieldDescribe.isNillable()) {
                        List<Schema.SObjectType> referenceTo = fieldDescribe.getReferenceTo();
                        if (!referenceTo.isEmpty()) {
                            String parentObjectApiName = referenceTo[0].getDescribe().getName();
                            // Recursively create and insert parent record if not already processing
                            if (!processingObjects.contains(parentObjectApiName)) {
                                List<SObject> parentRecords = populateFields(parentObjectApiName, 1, null);
                                if (!parentRecords.isEmpty()) {
                                    try {
                                        insert parentRecords[0];
                                        obj.put(fieldName, parentRecords[0].Id);
                                    } catch (DmlException e) {
                                        System.debug('Error inserting parent record ' + parentObjectApiName + ': ' + e.getMessage());
                                        // Fallback to null or handle error as appropriate
                                    }
                                }
                            }
                        }
                    } else if (!fieldDescribe.isNillable()) {
                        Object testValue = getTestValue(fieldDescribe, i);
                        obj.put(fieldName, testValue);
                    }
                    Object testValue = getTestValue(fieldDescribe, i);
                    obj.put(fieldName, testValue);
                }
            }
            records.add(obj);
        }
        processingObjects.remove(objectApiName); // Remove from processing set after completion
        return records;
    }
    
    /**
     * Returns a test value for a field based on its data type.
     * 
     * @param fieldDescribe Describe information of the field.
     * @param index Index for generating unique values.
     * @return Test value for the field.
     */
    private static Object getTestValue(Schema.DescribeFieldResult fieldDescribe, Integer index) {
        Schema.DisplayType fieldType = fieldDescribe.getType();
        
        // Check for default values for common fields
        if (defaultFieldValues.containsKey(fieldDescribe.getName())) {
            return defaultFieldValues.get(fieldDescribe.getName());
        }

        switch on fieldType {
            when STRING, TEXTAREA, ENCRYPTEDSTRING {
                return 'Test ' + fieldDescribe.getLabel() + ' ' + index + ' ' + System.currentTimeMillis();
            }
            when PICKLIST {
                List<Schema.PicklistEntry> picklistValues = fieldDescribe.getPicklistValues();
                return picklistValues.isEmpty() ? null : picklistValues[0].getValue();
            }
            when MULTIPICKLIST {
                List<Schema.PicklistEntry> picklistValues = fieldDescribe.getPicklistValues();
                if (!picklistValues.isEmpty()) {
                    // Return a comma-separated string of the first few values
                    List<String> selectedValues = new List<String>();
                    for (Integer i = 0; i < Math.min(picklistValues.size(), 2); i++) {
                        selectedValues.add(picklistValues[i].getValue());
                    }
                    return String.join(selectedValues, ';');
                }
                return null;
            }
            when BOOLEAN {
                return true;
            }
            when DATE {
                return Date.today();
            }
            when DATETIME {
                return DateTime.now();
            }
            when CURRENCY, DOUBLE, PERCENT {
                return 100.00 + index;
            }
            when INTEGER {
                return 100 + index;
            }
            when PHONE {
                return '555-123-' + String.valueOf(1000 + index);
            }
            when EMAIL {
                return 'test' + index + System.currentTimeMillis() + '@example.com';
            }
            when URL {
                return 'https://www.example' + index + System.currentTimeMillis() + '.com';
            }
            when ID {
                // For ID fields that are not lookups (e.g., External ID fields if not handled as reference)
                return 'a00000000000000' + String.valueOf(index);
            }
            when TEXT {
                return 'Test Text ' + index;
            }
            when ADDRESS {
                // Return a simple address map
                Map<String, Object> addressMap = new Map<String, Object>();
                addressMap.put('street', '123 Test St');
                addressMap.put('city', 'Testville');
                addressMap.put('state', 'CA');
                addressMap.put('postalCode', '90210');
                addressMap.put('country', 'USA');
                return addressMap;
            }
            when else {
                System.debug('Unhandled field type: ' + fieldType + ' for field: ' + fieldDescribe.getName());
                return null;
            }
        }
    }
}