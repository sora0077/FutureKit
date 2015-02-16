//
//  Future.swift
//  FutureKit
//
//  Created by 林達也 on 2015/02/14.
//  Copyright (c) 2015年 林達也. All rights reserved.
//

import Foundation

let future_queue = {
    dispatch_queue_create("jp.sora0077.future.queue-\(arc4random_uniform(UInt32.max))", nil)!
}

func safe_queue_sync(queue: dispatch_queue_t, block: dispatch_block_t) {
    
    let queue_label = dispatch_queue_get_label(queue)
    let current_label = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)
    if queue_label != current_label {
        dispatch_sync(queue, block)
    } else {
        block()
    }
}

final class Box<T> {
    
    let unbox: T
    
    init(_ v: T) {
        self.unbox = v
    }
}

enum FailableOf<T> {
    
    case Success(Box<T>)
    case Failure(NSError)
}

/**
*  
*/
public final class Future<T> {
    
    typealias Deferred = (resolve: T -> Void, reject: NSError -> Void) -> Void
    let deferred: Deferred
    
    var queue: dispatch_queue_t
    
    var failableOf: FailableOf<T>?
    
    /// isReady
    public internal(set) var isReady: Bool = true
    /// isExecuting
    public internal(set) var isExecuting: Bool = false
    /// isFinished
    public internal(set) var isFinished: Bool = false
    
    /**
    init
    
    :param: block <#block description#>
    
    :returns: <#return value description#>
    */
    public convenience init(_ block: Deferred) {
        
        self.init(block, queue: future_queue())
    }
    
    init(_ block: Deferred, queue: dispatch_queue_t) {
        
        self.deferred = block
        self.queue = queue
    }
    
    /**
    resolve
    
    :param: v <#v description#>
    
    :returns: <#return value description#>
    */
    public class func resolve(v: T) -> Self {
        
        return self({ deferred in
            deferred.resolve(v)
        })
    }
    
    /**
    reject
    
    :param: e <#e description#>
    
    :returns: <#return value description#>
    */
    public class func reject(e: NSError) -> Self {
        
        return self({ deferred in
            deferred.reject(e)
        })
    }
    
    /**
    map
    
    :param: transform <#transform description#>
    
    :returns: <#return value description#>
    */
    public func map<U>(transform: T -> U) -> Future<U> {
        
        return Future<U>({ deferred in
            self._eval { f in
                switch f {
                case let .Success(box):
                    deferred.resolve(transform(box.unbox))
                case let .Failure(error):
                    deferred.reject(error)
                }
            }
        }, queue: self.queue)
    }
    
    /**
    map
    
    :param: transform <#transform description#>
    
    :returns: <#return value description#>
    */
    public func map<U>(transform: T -> Future<U>) -> Future<U> {
        
        return Future<U>({ deferred in
            self._eval { f in
                switch f {
                case let .Success(box):
                    let promise = transform(box.unbox)
                    promise.queue = self.queue
                    promise._eval { f in
                        switch f {
                        case let .Success(box):
                            deferred.resolve(box.unbox)
                        case let .Failure(error):
                            deferred.reject(error)
                        }
                    }
                case let .Failure(error):
                    deferred.reject(error)
                }
            }
        }, queue: self.queue)
    }
    
    /**
    recover
    
    :param: transform <#transform description#>
    
    :returns: <#return value description#>
    */
    public func recover(transform: NSError -> Future) -> Future {
        
        return Future({ deferred in
            self._eval { f in
                switch f {
                case let .Success(box):
                    deferred.resolve(box.unbox)
                case let .Failure(error):
                    let promise = transform(error)
                    promise.queue = self.queue
                    promise._eval { f in
                        switch f {
                        case let .Success(box):
                            deferred.resolve(box.unbox)
                        case let .Failure(error):
                            deferred.reject(error)
                        }
                    }
                }
            }
        }, queue: self.queue)
    }
    
    /**
    eval
    
    :param: success <#success description#>
    
    :returns: <#return value description#>
    */
    public func eval(success: T -> Void) -> Self {
        
        self._eval { f in
            switch f {
            case let .Success(box):
                success(box.unbox)
            case .Failure:
                break
            }
        }
        return self
    }
    
    /**
    fail
    
    :param: failure <#failure description#>
    
    :returns: <#return value description#>
    */
    public func fail(failure: NSError -> Void) -> Self {
        
        self._eval { f in
            switch f {
            case .Success:
                break
            case let .Failure(error):
                failure(error)
            }
        }
        return self
    }
    
    func _eval(f: FailableOf<T> -> Void) {
        
        dispatch_async(self.queue) {
            if let failableOf = self.failableOf {
                f(failableOf)
            } else {
                self.isReady = false
                self.isExecuting = true
                let resolve: T -> Void = { v in
                    
                    safe_queue_sync(self.queue) {
                        self.failableOf = .Success(Box(v))
                        f(self.failableOf!)
                        self.isExecuting = false
                        self.isFinished = true
                    }
                }
                let reject: NSError -> Void = { e in
                    
                    safe_queue_sync(self.queue) {
                        self.failableOf = .Failure(e)
                        f(self.failableOf!)
                        self.isExecuting = false
                        self.isFinished = true
                    }
                }
                self.deferred(resolve: resolve, reject: reject)
            }
        }
    }
}

/**
zip

:param: fu <#fu description#>
:param: fv <#fv description#>

:returns: <#return value description#>
*/
public func zip<U, V>(fu: Future<U>, fv: Future<V>) -> Future<(U, V)> {
    
    return Future<(U, V)>({ deferred in
        
        var results: (U?, V?) = (nil, nil)
        var errors: (NSError?, NSError?) = (nil, nil)
        
        let serial = dispatch_queue_create("jp.sora0077.future.queue-zip", nil)
        
        fu.eval({ lhs in
            dispatch_async(serial) {
                if let v = results.1 {
                    deferred.resolve((lhs, v))
                } else {
                    results.0 = lhs
                }
            }
        }).fail({ e in
            dispatch_async(serial) {
                errors.0 = e
                if errors.1 == nil {
                    deferred.reject(e)
                }
            }
        })
        
        fv.eval({ lhs in
            dispatch_async(serial) {
                if let u = results.0 {
                    deferred.resolve((u, lhs))
                } else {
                    results.1 = lhs
                }
            }
        }).fail({ e in
            dispatch_async(serial) {
                errors.1 = e
                if errors.0 == nil {
                    deferred.reject(e)
                }
            }
        })
    })
}

/**
zip

:param: fx <#fx description#>
:param: fy <#fy description#>
:param: fz <#fz description#>

:returns: <#return value description#>
*/
public func zip<X, Y, Z>(fx: Future<X>, fy: Future<Y>, fz: Future<Z>) -> Future<(X, Y, Z)> {
    
    let zipped = zip(zip(fx, fy), fz)
    return zipped.map({ lhs in
        (lhs.0.0, lhs.0.1, lhs.1)
    })
}

/**
zip

:param: fx <#fx description#>
:param: fy <#fy description#>
:param: fz <#fz description#>
:param: fw <#fw description#>

:returns: <#return value description#>
*/
public func zip<X, Y, Z, W>(fx: Future<X>, fy: Future<Y>, fz: Future<Z>, fw: Future<W>) -> Future<(X, Y, Z, W)> {
    
    let zipped = zip(zip(fx, fy), zip(fz, fw))
    return zipped.map({ lhs in
        (lhs.0.0, lhs.0.1, lhs.1.0, lhs.1.1)
    })
}

