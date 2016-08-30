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
import Alamofire

enum APILayerError: ErrorType {
    case RequestFailedWithJSONValue(statusCode: Int, jsonValue: AnyObject)
}

// Setting the delegate is optional. If set, it can control how the API handles auth token refreshing
public protocol TokenRefreshDelegate {
    
    // For each response the delegate is asked if it implies that token refresh is neeed. Could check for HTTP status for example.
    func tokenRefreshIsIndicated(byResponse response: NSHTTPURLResponse) -> Bool
    
    // Must refresh the token and call the completion block on failure or succcess. Should do a refresh request.
    // If refresh was successful, the waiting requests are performed in order and everything goes on. If however
    // refreshing failed, all waiting requests are cancelled and the delegates tokenRefreshHasFailed() method is called,
    // so that the app can react to that (log out for example).
    func tokenRefresh(completion: (refreshWasSuccessful: Bool) -> ())
    
    // Called if token refresh has failed. In this case all waiting requests are removed and the app should react to that.
    func tokenRefreshHasFailed()
}

// Wrapper to make NSURLRequest conform to URLRequestConvertible
class RequestWrapper: URLRequestConvertible {
    let request: NSMutableURLRequest
    init(request: NSMutableURLRequest) {
        self.request = request
    }
    
    var URLRequest: NSMutableURLRequest { return request }
}

// This class functions as the main interface to the API layer.
public class API {
    
    // Custom manager, for example if you need security policy exceptions when using unsigned SSL certificates on the backend
    public static var customManager: Alamofire.Manager?
    
    // Mapper
    public static var mapper = Mapper()
    
    // If this one is set it might return mock paths for router cases, in which case the API does use mock data from local filesystem
    public static var mocker: MockProtocol?
    
    // The optional delegate, that controls token refresh logic
    public static var tokenRefreshDelegate: TokenRefreshDelegate?

    // This queue is used to delay requests when a token refresh is needed. The requests are then performed after the refresh is done.
    private static var operations = NSOperationQueue()
    
    // If this is set, we are currently refreshing the token
    private static var tokenRefreshOperation: NSOperation?
    
    // MARK: Request creation from routers

    private class func createRequest(forRouter router: RouterProtocol) -> Request {
        
        // Make sure the operation queue is sequential
        API.operations.maxConcurrentOperationCount = 1
        
        // Get base URL
        let URL = NSURL(string: router.path, relativeToURL: NSURL(string: router.baseURLString))
        
        // Create request
        let mutableURLRequest = NSMutableURLRequest(URL: URL!)

        // Get method for this case
        mutableURLRequest.HTTPMethod = router.method.rawValue
        
        // Add optional header values
        for (headerKey, headerValue) in API.mapper.headersForRouter(router) {
            mutableURLRequest.addValue(headerValue, forHTTPHeaderField: headerKey)
        }
        
        let parameters = API.mapper.parametersForRouter(router)
        let encoding = router.encoding
        let requestTuple = encoding.encode(mutableURLRequest, parameters: parameters)

        if let customManager = API.customManager {
            return customManager.request(RequestWrapper(request: requestTuple.0))
        } else {
            return Alamofire.request(RequestWrapper(request: requestTuple.0))
        }
    }
    
    // MARK: Request performing 
    
    internal class func performRouter(router: RouterProtocol, complete: (NSURLRequest?, NSHTTPURLResponse?, MappableObject?, APIResponseStatus) -> ()) {
        
        // Do the actual request
        let request = API.createRequest(forRouter: router)

        if let uploadData = router.uploadData {
            // Data uploads are using a multipart request
            
            // TODO: Needs token refresh logic!
            
            if let urlRequest = request.request {
                Alamofire.upload(urlRequest,
                    
                    multipartFormData: { (formData: MultipartFormData) -> Void in
                        formData.appendBodyPart(data: uploadData.data, name: uploadData.name, fileName: uploadData.fileName, mimeType: uploadData.mimeType)
                    },
                    
                    encodingMemoryThreshold: Manager.MultipartFormDataEncodingMemoryThreshold,
                    
                    encodingCompletion: { (encodingResult) -> Void in
                        
                        switch encodingResult {
                        case .Success(let uploadRequest, _, _):
                            
                            uploadRequest.responseJSON(completionHandler: { response in
                                uploadRequest.handleJSONCompletion(router, response: response, completionHandler: complete)
                            })
                            
                        case .Failure(let encodingError):
                            // TODO: Need better description here
                            complete(nil, nil, nil, APIResponseStatus.EncodingError(description: "Failed"))
                        }
                    }
                )
            }
            
        } else {
            
            // Get the response object
            request.responseObject(router) { (request: NSURLRequest?, response: NSHTTPURLResponse?, result: MappableObject?, status: APIResponseStatus) in
                
                if let response = response, let tokenRefreshDelegate = self.tokenRefreshDelegate {
                    
                    if tokenRefreshDelegate.tokenRefreshIsIndicated(byResponse: response) {
                        
                        // Create the token refresh operation
                        API.tokenRefreshOperation = TokenRefreshOperation(tokenRefreshDelegate: tokenRefreshDelegate, completion: { (refreshWasSuccessful) -> () in
                            
                            if refreshWasSuccessful == false {
                                // Refreshing failed, let the delegate know
                                tokenRefreshDelegate.tokenRefreshHasFailed()
                                // And cancel all
                                API.operations.cancelAllOperations()
                            }
                            
                            // Reset refresh operation
                            API.tokenRefreshOperation = nil
                        })
                        
                        // Enqueue the token refresh operation
                        API.operations.addOperation(API.tokenRefreshOperation!)
                        
                        // Enqueue the router, so that after the token refresh it is redone
                        self.enqueueRouter(router, complete: complete)
                        
                        // Do not call the complete block yet
                        return
                    }
                }
                
                // No refresh needed, status is in the success area.
                complete(request, response, result, status)
            }
        }
    }
    
    // MARK: Request enqueueing
    
    private class func enqueueRouter(router: RouterProtocol, complete: (NSURLRequest?, NSHTTPURLResponse?, result: MappableObject?, status: APIResponseStatus) -> ()) {
        
        var routerOperation: NSOperation?
        
        if router.blockedOperation {
            routerOperation = BlockedRouterOperation(router: router, completion: complete)
        } else {
            routerOperation = NSBlockOperation(block: {
                self.performRouter(router, complete: complete)
            })
        }
        
        if let tokenRefreshOperation = API.tokenRefreshOperation {
            routerOperation?.addDependency(tokenRefreshOperation)
        }

        if let routerOperation = routerOperation {
            API.operations.addOperation(routerOperation)
        }
    }
    
    // MARK: Private request method. If there is a mocker, looks there. If not existing, enqueues the router.
    
    private class func completeRequest(router: RouterProtocol, complete: (NSURLRequest?, NSHTTPURLResponse?, MappableObject?, APIResponseStatus) -> ()) {
        
        if let mocker = API.mocker, let path = mocker.path(forRouter: router) {
            let request = API.createRequest(forRouter: router)
            
            request.mockObject(forPath: path, withRouter: router, completionHandler: { (result, status) -> Void in
                complete(nil, nil, result, status)
            })
        }
        else {
            enqueueRouter(router, complete: complete)
        }
    }
    
    // MARK: Public request methods
    
    public class func tokenRefresh(router: RouterProtocol, complete: (result: MappableObject?, status: APIResponseStatus) -> ()) {

        // This method must be used by the actual token refresh logic in the app. 
        // It does not use the operation queue used for other requests.
        // Very important, because this method does NOT enqueue the request. While token 
        // refresh is working all enqueued requests are waiting for the token refresh to finish
        // by calling the completion(refreshWasSuccessful: Bool).
        
        let request = API.createRequest(forRouter: router)
        
        request.responseObject(router) { (request, response, result, status) -> Void in
            complete(result: result, status: status)
        }
        
    }
    
    // Performs request with the specified Router. Completion block is called in case of success / failure later on.
    public class func request(router: RouterProtocol, complete: (result: MappableObject?, status: APIResponseStatus) -> ()) {
        
        API.completeRequest(router) { (urlRequest, urlResponse, result: MappableObject?, status: APIResponseStatus) -> () in
            complete(result: result, status: status)
        }
    }

    // Performs request with the specified Router. Completion block is called in case of success / failure later on.
    // This version also gives the http response to the completion block
    public class func request(router: RouterProtocol, complete: (result: MappableObject?, status: APIResponseStatus, urlResponse: NSHTTPURLResponse?) -> ()) {

        API.completeRequest(router) { (urlRequest, urlResponse, result, status) -> () in
            complete(result: result, status: status, urlResponse: urlResponse)
        }

    }
    
    // MARK: Methods to help with debugging
    

    public class func requestString(router: RouterProtocol, complete: (String?, ErrorType?) -> ()) {
        
        let request = API.createRequest(forRouter: router)
        
        request.responseString { response in            
            print("Response String: \(response.result.value)")
            complete(response.result.value, nil)
        }
    }
    
    // Performs request with the specified Router. Completion block is called in case of success / failure later on.
    public class func requestStatus(router: RouterProtocol, complete: (Int?, ErrorType?) -> ()) {
        
        let request = API.createRequest(forRouter: router)
        
//        request.responseString { response in
//            print("Response String: \(response.result.value)")
//        }
//        
        
        request.response { (urlRequest, urlResponse, data, errorType) -> Void in
            let statusCode = urlResponse?.statusCode
            complete(statusCode, errorType)
        }
        
    }
    
}
