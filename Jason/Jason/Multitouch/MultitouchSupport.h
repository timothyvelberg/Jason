//
//  MultitouchSupport.h
//  Jason
//
//  Bridge header for private MultitouchSupport framework
//

#ifndef MultitouchSupport_h
#define MultitouchSupport_h

#import <Foundation/Foundation.h>

// Opaque type for multitouch device
typedef void* MTDeviceRef;

// Touch state constants
typedef enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7
} MTTouchState;

// Structure representing a single touch point
// Note: This struct must match the exact memory layout used by MultitouchSupport framework
typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerID;
    int handID;
    float normalizedX;    // 0.0 to 1.0
    float normalizedY;    // 0.0 to 1.0
    float size;
    int field10;
    float angle;
    float majorAxis;
    float minorAxis;
    float field14;
    int field15;
    int field16;
    float zTotal;
    int field18;
    int field19;
    float field20;
} MTTouch;

// Callback function type
typedef void (*MTContactFrameCallback)(MTDeviceRef device, MTTouch* _Nullable touches, int numTouches, double timestamp, int frame, void* refcon);

// =============================================================================
// Path API (experimental - for per-finger tracking)
// =============================================================================

// Opaque types for path-based tracking
typedef void* MTPathRef;
typedef void* MTContactRef;

// Path callback function type
typedef void (*MTPathCallback)(MTDeviceRef device, long pathID, int state, MTPathRef path);

// =============================================================================
// Framework functions
// =============================================================================

#ifdef __cplusplus
extern "C" {
#endif

// Get list of multitouch devices
CFMutableArrayRef MTDeviceCreateList(void);

// Register callback for touch events
void MTRegisterContactFrameCallback(MTDeviceRef device, MTContactFrameCallback callback);
void MTUnregisterContactFrameCallback(MTDeviceRef device, MTContactFrameCallback callback);

// Start/stop receiving touch events
void MTDeviceStart(MTDeviceRef device, int unknown);
void MTDeviceStop(MTDeviceRef device);

// Check if device is built-in trackpad
Boolean MTDeviceIsBuiltIn(MTDeviceRef device);

// Release device
void MTDeviceRelease(MTDeviceRef device);

// Path-based tracking (experimental)
void MTRegisterPathCallback(MTDeviceRef device, MTPathCallback callback);
void MTUnregisterPathCallback(MTDeviceRef device, MTPathCallback callback);

// Path accessors - return contact at specific lifecycle points
MTContactRef MTPath_getMakeContact(MTPathRef path);
MTContactRef MTPath_getTouchdownContact(MTPathRef path);
MTContactRef MTPath_getBreakContact(MTPathRef path);
MTContactRef MTPath_getLiftoffContact(MTPathRef path);

// Contact accessors
void MTContact_getCentroidPixel(MTContactRef contact, float* x, float* y);
bool MTContact_isActive(MTContactRef contact);

#ifdef __cplusplus
}
#endif

#endif /* MultitouchSupport_h */
