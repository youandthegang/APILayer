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

// We unfortunately have to use this extra class for collection parsing because Swift has problems with
// generic types being used as generic types (A<T> as <T> in another class / method).
open class CollectionResponse: MappableObject {
    
    open let items: [AnyObject]
    
    required public init(map: Map) {
        
        let itemsKey = API.mapper.collectionResponseItemsKey
        
        if let itemsArray = map.representation.value(forKeyPath: itemsKey) as? [AnyObject] {
            // JSON is a dictionary at top level and contains the default items key
            items = itemsArray
        }
        else if let itemsArray = map.representation as? [AnyObject] {
            // JSON is an array at top level
            items = itemsArray
        }
        else {
            // None of the two cases, so that failed.
            items = []
            map.error = APIResponseStatus.missingKey(description: "The '\(itemsKey)' key is missing in this collection response" )
        }
    }
    
}
