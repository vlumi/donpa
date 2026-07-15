import DonpaCore
import Foundation

#if os(iOS)
import UIKit
#endif

/// The live platform facts the device registry publishes.
enum DeviceFacts {
    static func current() -> DeviceInfo.Facts {
        #if os(iOS)
        // iOS 16 returns a generic name without the user-assigned-device-name
        // entitlement — good enough until the devices UI justifies requesting it.
        let name = UIDevice.current.name
        let cls: DeviceInfo.DeviceClass =
            UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
        var uts = utsname()
        uname(&uts)
        let model = withUnsafeBytes(of: &uts.machine) { raw in
            String(bytes: raw.prefix(while: { $0 != 0 }), encoding: .utf8) ?? "iOS"
        }
        return DeviceInfo.Facts(name: name, model: model, deviceClass: cls)
        #else
        let name = Host.current().localizedName ?? "Mac"
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var chars = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &chars, &size, nil, 0)
        let model = String(cString: chars)
        return DeviceInfo.Facts(name: name, model: model, deviceClass: .mac)
        #endif
    }
}
