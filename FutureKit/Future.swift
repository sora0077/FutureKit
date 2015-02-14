//
//  Future.swift
//  FutureKit
//
//  Created by 林達也 on 2015/02/14.
//  Copyright (c) 2015年 林達也. All rights reserved.
//

import Foundation


private let future_queue = dispatch_queue_create("jp.sora0077.future.queue", nil)

final class Box<T> {
    
    let unbox: T
    
    init(_ v: T) {
        self.unbox = v
    }
}

enum FailableOf<T> {
    
    case Success(Box<T>)
    case Failure(NSError)
    
    var value: T {
        
        switch self {
        case let .Success(box):
            return box.unbox
        case let .Failure(error):
            fatalError("\(error)")
        }
    }
    
    var error: NSError {
        
        switch self {
        case let .Success(box):
            fatalError("\(box.unbox)")
        case let .Failure(error):
            return error
        }
    }
}

/*
*
*/
public final class Future<T> {
    
    typealias Deferred = (resolve: T -> Void, reject: NSError -> Void) -> Void
    let deferred: Deferred
    
    var failableOf: FailableOf<T>?
    
    public init(_ block: Deferred) {
        
        self.deferred = block
    }
    
    public class func resolve(v: T) -> Self {
        
        return self({ deferred in
            deferred.resolve(v)
        })
    }
    
    public class func reject(e: NSError) -> Self {
        
        return self({ deferred in
            deferred.reject(e)
        })
    }
    
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
        })
    }
    
    public func map<U>(transform: T -> Future<U>) -> Future<U> {
        
        return Future<U>({ deferred in
            self._eval { f in
                switch f {
                case let .Success(box):
                    let promise = transform(box.unbox)
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
        })
    }
    
    public func recover(transform: NSError -> Future) -> Future {
        
        return Future({ deferred in
            self._eval { f in
                switch f {
                case let .Success(box):
                    deferred.resolve(box.unbox)
                case let .Failure(error):
                    let promise = transform(error)
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
        })
    }
    
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
        
        dispatch_async(future_queue) {
            if let failableOf = self.failableOf {
                f(failableOf)
            } else {
                let resolve: T -> Void = { v in
                    self.failableOf = .Success(Box(v))
                    f(self.failableOf!)
                }
                let reject: NSError -> Void = { e in
                    self.failableOf = .Failure(e)
                    f(self.failableOf!)
                }
                self.deferred(resolve: resolve, reject: reject)
            }
        }
    }
    
    func _eval() {
        
        dispatch_async(future_queue) {
            self.deferred(resolve: { _ in }, reject: { _ in })
        }
    }
}