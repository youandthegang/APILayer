// The MIT License (MIT)
//
// Copyright (c) 2015 you & the gang UG(haftungsbeschränkt)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Foundation

// MARK : required protocols and extensions for generic to implement T() as an initializer
public protocol Defaultable {init()}
extension Int: Defaultable {}
extension String: Defaultable {}
extension NSDate: Defaultable {}
extension Float: Defaultable {}
extension Double: Defaultable {}
extension Bool: Defaultable {}
extension Optional: Defaultable {}

public class ParameterMapper {        
    
    var dateFormatter: NSDateFormatter = NSDateFormatter()
    
    // Function for populating a 'let' property. i.e. returns property or returns default property and sets 'error' to a value
    public final func valueFromRepresentation<T: Defaultable>(representation: AnyObject, key: String, error: UnsafeMutablePointer<NSError?>) -> T {
        
        if let value = representation.valueForKeyPath(key) as? T {
            return value
        }
        
        let errorDescription = "Could not extract value for key \(key). Key is missing."
        error.memory = NSError(domain: "APILayer.ParameterMapper.\(__FUNCTION__)", code: 0x1, userInfo: [NSLocalizedDescriptionKey: errorDescription, NSLocalizedFailureReasonErrorKey: representation])
        
        return T()
    }
    
    // Function for populating a 'var' property. i.e. returns property or nil
    public final func valueFromRepresentation<T: Defaultable>(representation: AnyObject, key: String) -> T? {
        if let value = representation.valueForKeyPath(key) as? T {
            return value
        }
        
        return nil
    }
    
    public final func dateFromRepresentation(representation: AnyObject, key: String) -> NSDate? {
        if let value = representation.valueForKeyPath(key) as? String {
            if let date = dateFormatter.dateFromString(value) {
                return date
            }
            println("Invalid 'dateString'!!")
        }
        return nil
    }
    
    public final func dateFromRepresentation(representation: AnyObject, key: String, error: UnsafeMutablePointer<NSError?>) -> NSDate {
        if let value = representation.valueForKeyPath(key) as? String {
            if let date = dateFormatter.dateFromString(value) {
                return date
            }
            
            let errorDescription = "Could not parse date for key '\(key)'. Date formatter might not recognize format."
            error.memory = NSError(domain: "APILayer.ParameterMapper.\(__FUNCTION__)", code: 0x1, userInfo: [NSLocalizedDescriptionKey: errorDescription, NSLocalizedFailureReasonErrorKey: representation])
            
            return NSDate()
            
        }

        let errorDescription = "Could not extract value for key '\(key)'. Key is missing."
        error.memory = NSError(domain: "APILayer.ParameterMapper.\(__FUNCTION__)", code: 0x1, userInfo: [NSLocalizedDescriptionKey: errorDescription, NSLocalizedFailureReasonErrorKey: representation])
        
        return NSDate()
    }
    
    public final func stringFromDate(date: NSDate) -> String {
        return dateFormatter.stringFromDate(date)
    }
    
    public func parametersForRouter(router: RouterProtocol) -> [String : AnyObject] {
        println("You need to implement this method in your ParameterMapper subclass")
        return [:]
    }
}