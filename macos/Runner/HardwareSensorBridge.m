#import "HardwareSensorBridge.h"

/// IOHID の検索条件に一致するサービスを作成して温度センサー値を収集します。
NSDictionary<NSString *, NSNumber *> *AppleSiliconTemperatureSensors(int32_t page, int32_t usage, int32_t type) {
    NSDictionary *dictionary = @{
        @"PrimaryUsagePage": @(page),
        @"PrimaryUsage": @(usage),
    };

    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (system == nil) {
        return @{};
    }

    IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)dictionary);
    NSDictionary<NSString *, NSNumber *> *result = AppleSiliconTemperatureSensorsFromSystemClient(system, type);
    CFRelease(system);
    return result;
}

/// IOHID サービスを走査し、取得できた温度イベントをセンサー名ごとに平均化します。
NSDictionary<NSString *, NSNumber *> *AppleSiliconTemperatureSensorsFromSystemClient(IOHIDEventSystemClientRef system, int32_t type) {
    if (system == nil) {
        return @{};
    }

    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (services == nil) {
        return @{};
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
    return result;
}
