//
//  Jason-Bridging-Header.h
//  Jason
//
//  Bridging header for Objective-C imports
//

#ifndef Jason_Bridging_Header_h
#define Jason_Bridging_Header_h

#import "MultitouchSupport.h"
#import <ApplicationServices/ApplicationServices.h>

// Private API: retrieves the CGWindowID for an AXUIElement window.
// Stable and widely used despite being private.
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *identifier);

#endif /* Jason_Bridging_Header_h */
