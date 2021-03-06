//
//  MDFlickrApiToken.m
//  Flickr Uploader
//
//  Created by Jānis Kiršteins on 16.06.13.
//  Copyright (c) 2013. g. SIA MONTA DIGITAL. All rights reserved.
//

#import "ARCKeychainGenericPasswordWrapper.h"
#import <Security/Security.h>

/*
 
 These are the default constants and their respective types,
 available for the kSecClassGenericPassword Keychain Item class:
 
 kSecAttrAccessGroup			-		CFStringRef
 kSecAttrCreationDate		-		CFDateRef
 kSecAttrModificationDate    -		CFDateRef
 kSecAttrDescription			-		CFStringRef
 kSecAttrComment				-		CFStringRef
 kSecAttrCreator				-		CFNumberRef
 kSecAttrType                -		CFNumberRef
 kSecAttrLabel				-		CFStringRef
 kSecAttrIsInvisible			-		CFBooleanRef
 kSecAttrIsNegative			-		CFBooleanRef
 kSecAttrAccount				-		CFStringRef
 kSecAttrService				-		CFStringRef
 kSecAttrGeneric				-		CFDataRef
 
 See the header file Security/SecItem.h for more details.
 
 */

@interface ARCKeychainGenericPasswordWrapper (PrivateMethods)
/*
 The decision behind the following two methods (secItemFormatToDictionary and dictionaryToSecItemFormat) was
 to encapsulate the transition between what the detail view controller was expecting (NSString *) and what the
 Keychain API expects as a validly constructed container class.
 */
- (NSMutableDictionary *)secItemFormatToDictionary:(NSDictionary *)dictionaryToConvert;
- (NSMutableDictionary *)dictionaryToSecItemFormat:(NSDictionary *)dictionaryToConvert;

// Updates the item in the keychain, or adds it if it doesn't exist.
- (void)writeToKeychain;

@end

@implementation ARCKeychainGenericPasswordWrapper
{
    NSMutableDictionary *keychainItemData;		// The actual keychain item data backing store.
    NSMutableDictionary *genericPasswordQuery;	// A placeholder for the generic keychain item query used to locate the item.
}

- (id)initWithService: (NSString *)service andAccount:(NSString*)account andAccessGroup:(NSString *) accessGroup;
{
    if (self = [super init])
    {
        // Begin Keychain search setup. The genericPasswordQuery leverages the special user
        // defined attribute kSecAttrGeneric to distinguish itself between other generic Keychain
        // items which may be included by the same application.
        genericPasswordQuery = [[NSMutableDictionary alloc] init];
        
        // see http://stackoverflow.com/questions/11614047/what-makes-a-keychain-item-unique-in-ios
		genericPasswordQuery[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
        genericPasswordQuery[(__bridge id)kSecAttrAccount] = account;
        genericPasswordQuery[(__bridge id)kSecAttrService] = service;
		
		// The keychain access group attribute determines if this item can be shared
		// amongst multiple apps whose code signing entitlements contain the same keychain access group.
		if (accessGroup != nil)
		{
#if TARGET_IPHONE_SIMULATOR
			// Ignore the access group if running on the iPhone simulator.
			//
			// Apps that are built for the simulator aren't signed, so there's no keychain access group
			// for the simulator to check. This means that all apps can see all keychain items when run
			// on the simulator.
			//
			// If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
			// simulator will return -25243 (errSecNoAccessForItem).
#else
			genericPasswordQuery[(__bridge id)kSecAttrAccessGroup] = accessGroup;
#endif
		}
		
		// Use the proper search constants, return only the attributes of the first match.
        genericPasswordQuery[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
        genericPasswordQuery[(__bridge id)kSecReturnAttributes] = (__bridge id)kCFBooleanTrue;
        
        NSDictionary *tempQuery = [NSDictionary dictionaryWithDictionary:genericPasswordQuery];
        
        CFMutableDictionaryRef outDictionary = NULL;
        
        if (!SecItemCopyMatching((__bridge CFDictionaryRef)tempQuery, (CFTypeRef *)&outDictionary) == noErr)
        {
            // Stick these default values into keychain item if nothing found.
            [self resetKeychainItem];
			
			// Add the generic attribute and the keychain access group.
            keychainItemData[(__bridge id)kSecAttrAccount] = account;
            keychainItemData[(__bridge id)kSecAttrService] = service;

			if (accessGroup != nil)
			{
#if TARGET_IPHONE_SIMULATOR
				// Ignore the access group if running on the iPhone simulator.
				//
				// Apps that are built for the simulator aren't signed, so there's no keychain access group
				// for the simulator to check. This means that all apps can see all keychain items when run
				// on the simulator.
				//
				// If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
				// simulator will return -25243 (errSecNoAccessForItem).
#else
				keychainItemData[(__bridge id)kSecAttrAccessGroup] = accessGroup;
#endif
			}
		}
        else
        {
            // load the saved data from Keychain.
            keychainItemData = [self secItemFormatToDictionary:(__bridge NSDictionary *)outDictionary];
        }
		if(outDictionary) CFRelease(outDictionary);
    }
    
	return self;
}

- (void)setObject:(id)inObject forKey:(id)key
{
    if (inObject == nil) return;
    id currentObject = keychainItemData[key];
    if (![currentObject isEqual:inObject])
    {
        keychainItemData[key] = inObject;
        [self writeToKeychain];
    }
}

- (id)objectForKey:(id)key
{
    return keychainItemData[key];
}

- (void)resetKeychainItem
{
	OSStatus junk = noErr;
    if (!keychainItemData)
    {
        keychainItemData = [[NSMutableDictionary alloc] init];
    }
    else if (keychainItemData)
    {
        NSMutableDictionary *tempDictionary = [self dictionaryToSecItemFormat:keychainItemData];
		junk = SecItemDelete((__bridge CFDictionaryRef)tempDictionary);
        NSAssert( junk == noErr || junk == errSecItemNotFound, @"Problem deleting current dictionary." );
    }
    
    // Default attributes for keychain item.
    keychainItemData[(__bridge id)kSecAttrAccount] = @"";
    keychainItemData[(__bridge id)kSecAttrLabel] = @"";
    keychainItemData[(__bridge id)kSecAttrDescription] = @"";
    
	// Default data for keychain item.
    keychainItemData[(__bridge id)kSecValueData] = @"";
}

- (NSMutableDictionary *)dictionaryToSecItemFormat:(NSDictionary *)dictionaryToConvert
{
    // The assumption is that this method will be called with a properly populated dictionary
    // containing all the right key/value pairs for a SecItem.
    
    // Create a dictionary to return populated with the attributes and data.
    NSMutableDictionary *returnDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionaryToConvert];
    
    // Add the Generic Password keychain item class attribute.
    returnDictionary[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    
    // Convert the NSString to NSData to meet the requirements for the value type kSecValueData.
	// This is where to store sensitive data that should be encrypted.
    NSString *passwordString = dictionaryToConvert[(__bridge id)kSecValueData];
    returnDictionary[(__bridge id)kSecValueData] = [passwordString dataUsingEncoding:NSUTF8StringEncoding];
    
    return returnDictionary;
}

- (NSMutableDictionary *)secItemFormatToDictionary:(NSDictionary *)dictionaryToConvert
{
    // The assumption is that this method will be called with a properly populated dictionary
    // containing all the right key/value pairs for the UI element.
    
    // Create a dictionary to return populated with the attributes and data.
    NSMutableDictionary *returnDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionaryToConvert];
    
    // Add the proper search key and class attribute.
    returnDictionary[(__bridge id)kSecReturnData] = (__bridge id)kCFBooleanTrue;
    returnDictionary[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    
    // Acquire the password data from the attributes.
    CFDataRef passwordData = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)returnDictionary, (CFTypeRef *)&passwordData) == noErr)
    {
        // Remove the search, class, and identifier key/value, we don't need them anymore.
        [returnDictionary removeObjectForKey:(__bridge id)kSecReturnData];
        
        // Add the password to the dictionary, converting from NSData to NSString.
        NSString *password = [[NSString alloc] initWithBytes:[(__bridge NSData *)passwordData bytes] length:[(__bridge NSData *)passwordData length]
                                                    encoding:NSUTF8StringEncoding];
        returnDictionary[(__bridge id)kSecValueData] = password;
    }
    else
    {
        // Don't do anything if nothing is found.
        NSAssert(NO, @"Serious error, no matching item found in the keychain.\n");
    }
	if(passwordData) CFRelease(passwordData);
    
	return returnDictionary;
}

- (void)writeToKeychain
{
    CFDictionaryRef attributes = NULL;
    NSMutableDictionary *updateItem = nil;
	OSStatus result;
    
    if (SecItemCopyMatching((__bridge CFDictionaryRef)genericPasswordQuery, (CFTypeRef *)&attributes) == noErr)
    {
        // First we need the attributes from the Keychain.
        updateItem = [NSMutableDictionary dictionaryWithDictionary:(__bridge NSDictionary *)attributes];
        // Second we need to add the appropriate search key/values.
        updateItem[(__bridge id)kSecClass] = genericPasswordQuery[(__bridge id)kSecClass];
        
        // Lastly, we need to set up the updated attribute list being careful to remove the class.
        NSMutableDictionary *tempCheck = [self dictionaryToSecItemFormat:keychainItemData];
        [tempCheck removeObjectForKey:(__bridge id)kSecClass];
		
#if TARGET_IPHONE_SIMULATOR
		// Remove the access group if running on the iPhone simulator.
		//
		// Apps that are built for the simulator aren't signed, so there's no keychain access group
		// for the simulator to check. This means that all apps can see all keychain items when run
		// on the simulator.
		//
		// If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
		// simulator will return -25243 (errSecNoAccessForItem).
		//
		// The access group attribute will be included in items returned by SecItemCopyMatching,
		// which is why we need to remove it before updating the item.
		[tempCheck removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
#endif
        
        // An implicit assumption is that you can only update a single item at a time.
		
        result = SecItemUpdate((__bridge CFDictionaryRef)updateItem, (__bridge CFDictionaryRef)tempCheck);
		NSAssert( result == noErr, @"Couldn't update the Keychain Item." );
    }
    else
    {
        // No previous item found; add the new one.
        result = SecItemAdd((__bridge CFDictionaryRef)[self dictionaryToSecItemFormat:keychainItemData], NULL);
		NSAssert( result == noErr, @"Couldn't add the Keychain Item." );
    }
	
	if(attributes) CFRelease(attributes);
}
@end
