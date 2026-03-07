#import "HardwareSensorBridge.h"

NSDictionary<NSString *, NSNumber *> *AppleSiliconTemperatureSensors(int32_t page, int32_t usage, int32_t type) {
    NSDictionary *dictionary = @{
        @"PrimaryUsagePage": @(page),
        @"PrimaryUsage": @(usage),
    };

    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)dictionary);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (services == nil) {
        if (system != nil) {
            CFRelease(system);
        }
        return nil;
    }

    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *samples = [NSMutableDictionary dictionary];
    for (CFIndex index = 0; index < CFArrayGetCount(services); index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        NSString *name = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR("Product")));
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, type, 0, 0);
        if (name == nil || event == nil) {
            if (event != nil) {
                CFRelease(event);
            }
            continue;
        }

        double value = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(type));
        if (isnan(value) || isinf(value) || value < -1000 || value > 300) {
            CFRelease(event);
            continue;
        }

        if (samples[name] == nil) {
            samples[name] = [NSMutableArray array];
        }
        [samples[name] addObject:@(value)];
        CFRelease(event);
    }

    NSMutableDictionary<NSString *, NSNumber *> *result = [NSMutableDictionary dictionary];
    [samples enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableArray<NSNumber *> *values, BOOL *stop) {
        if (values.count == 0) {
            return;
        }

        double total = 0;
        for (NSNumber *value in values) {
            total += value.doubleValue;
        }
        result[key] = @(total / (double)values.count);
    }];

    CFRelease(services);
    CFRelease(system);

    return result;
}
