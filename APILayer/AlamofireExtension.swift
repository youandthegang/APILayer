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

// This code is based on the README of Alamofire (https://github.com/Alamofire/Alamofire).
// Thanks to Mattt Thompson for all the great stuff!

import Foundation
import Alamofire

@objc public protocol ResponseObjectSerializable {
    init(response: NSHTTPURLResponse, representation: AnyObject, error: UnsafeMutablePointer<NSError?>)
}

extension Alamofire.Request {
    
    // MARK: Parsing method
    
    public func responseObject<T: ResponseObjectSerializable>(completionHandler: (NSURLRequest, NSHTTPURLResponse?, T?, NSError?) -> Void) -> Self {
        let serializer: Serializer = { (request, response, data) in
            
            if response?.statusCode < 200 && response?.statusCode >= 300 {
                return (nil, NSError(domain: "httpStatus", code: 0, userInfo: nil))
            }
            
            let JSONSerializer = Request.JSONResponseSerializer(options: .AllowFragments)
            let (JSON: AnyObject?, serializationError) = JSONSerializer(request, response, data)
            
            if response != nil && JSON != nil {
                
                var error: NSError?
                
                let result = T(response: response!, representation: JSON!, error: &error)
                
                if let validError = error {
                    // Construct a new error, based on the internal errors userInfo dictionary and add the URL of the request
                    var newUserInfo = validError.userInfo ?? [NSObject : AnyObject]()
                    
                    newUserInfo[NSURLErrorKey] = request.URL.absoluteString
                    
                    return (nil, NSError(domain: validError.domain, code: validError.code, userInfo: newUserInfo))
                }
                else {
                    // No error, return result
                    return (result, nil)
                }
                
            } else {
                return (nil, serializationError)
            }
        }
        
        return response(serializer: serializer, completionHandler: { (request, response, object, error) in
            completionHandler(request, response, object as? T, error)
        })
    }    
    
}