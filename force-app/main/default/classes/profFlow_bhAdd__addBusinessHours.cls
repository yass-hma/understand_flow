/*
This file is generated and isn't the actual source code for this
managed global class.
This read-only file shows the class's global constructors,
methods, variables, and properties.
To enable code to compile, all methods return null.
*/
global class addBusinessHours {
    global addBusinessHours() {

    }
    @InvocableMethod(label='Professor Flow | Add Business Hours' description='Adds an interval of time from a start Datetime traversing business hours only. Returns the result Datetime in the local time zone.')
    global static List<profFlow_bhAdd.addBusinessHours.response> getUpdatedBusinessDate(List<profFlow_bhAdd.addBusinessHours.request> inputParams) {
        return null;
    }
global class request {
    @InvocableVariable(label='Business Hours Id' required=true)
    global String businessHoursId;
    @InvocableVariable(label='Interval To Add (Milliseconds)' required=true)
    global Long intervalMilliseconds;
    @InvocableVariable(label='Start Date' required=true)
    global Datetime startDateTime;
    global request() {

    }
}
global class response {
    @InvocableVariable(label='Next Business Date' required=false)
    global Datetime updatedBusinessDate;
    global response() {

    }
}
}
