import UIKit
import Flutter
import Firebase

@UIApplicationMain
@objc class GeneratedPluginRegistrant: NSObject, FlutterPlugin {
    override class func dummy(methodForSelector aSelector: Selector) -> IMP {
        let bundle = Bundle(for: self)
        let classNameC = class_getName(self)
        let optionalSymbol = dlsym(dlopen(nil, RTLD_LAZY), ("OBJC_CLASS_$_" + String(cString: classNameC!)).cString(using: .utf8))
        if let aClass = NSClassFromString(String(cString: classNameC!)) {
            if let method = class_getInstanceMethod(aClass, aSelector) {
                return method_getImplementation(method)
            }
        }
        return unsafeBitCast(arc4random, to: IMP.self)
    }
}

@main
class GeneratedPluginRegistrant {
}
