//
//  FutureKitTests.swift
//  FutureKitTests
//
//  Created by 林達也 on 2015/02/14.
//  Copyright (c) 2015年 林達也. All rights reserved.
//

import UIKit
import XCTest
//import FutureKit

class FutureKitTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func test_queue() {
        
        XCTAssertNotEqual(future_queue(), future_queue(), "")
    }
    
    func test_then() {
        var cnt = 0
        let counter = { ++cnt }
        
        self.wait { done in
            
            let p1 = Future.resolve(100)
            
            let p2 = p1.map({
                "\($0) \(counter()) to string"
            })
            
            p2.eval({ lhs in
                done()
            })
            
            return {
                XCTAssertEqual(1, cnt, "")
                XCTAssertEqual(p1.queue, p2.queue, "")
            }
        }
    }
    func test_then_resolveが間違って何度も呼ばれてもevalのブロックは一度だけ呼ばれる() {
        var cnt = 0
        let counter = { ++cnt }
        
        self.wait { done in
            
            let p1 = Future<Int>({ deferred in
                deferred.resolve(100)
                deferred.resolve(100)
                deferred.resolve(100)
            })
            
            let p2 = p1.map({
                "\($0) \(counter()) to string"
            })
            
            p2.eval({ lhs in
                counter()
                counter()
                counter()
                done()
            })
            
            return {
                XCTAssertEqual(4, cnt, "")
                XCTAssertEqual(p1.queue, p2.queue, "")
            }
        }
    }
    
    func test_then_オブジェクトが正しく開放されるか() {
        var cnt = 0
        let counter = { ++cnt }
        
        self.wait { done in
            
            weak var wp1: Future<Int>?
            weak var wp2: Future<String>?
            
            autoreleasepool {
                let p1 = Future { deferred in
                    dispatch_after(when(0.2), dispatch_get_main_queue()) {
                        deferred.resolve(100)
                    }
                }
                wp1 = p1
                
                let p2 = p1.map({
                    "\($0) \(counter()) to string"
                })
                wp2 = p2
                
                p2.eval({ lhs in
                    done()
                })
            }
            XCTAssertNotNil(wp1, "")
            XCTAssertNotNil(wp2, "")
            
            return {
                XCTAssertNil(wp1, "")
                XCTAssertNil(wp2, "")
                XCTAssertEqual(1, cnt, "")
            }
        }
    }
    
    func test_then_resolveは記憶される() {
        var cnt = 0
        let counter = { ++cnt }
        
        self.wait(till: 2) { done in
            
            let p1 = Future.resolve(101)
            
            let p2 = p1.map({
                "\($0) \(counter()) to string"
            })
            let p3 = p2.map({
                "\($0) \(counter()) to string"
            })
            
            p2.eval({ lhs in
                done()
                XCTAssertEqual(lhs, "101 1 to string", "")
//                XCTAssertTrue(p2.failableOf == nil, "")
            })
            p3.eval({ lhs in
                done()
                XCTAssertEqual(lhs, "101 1 to string 2 to string", "")
            })
            
            return {
                XCTAssertEqual(p2.queue, p3.queue, "")
                XCTAssertEqual(2, cnt, "")
            }
        }
    }
    
    func test_評価しない場合_中身は実行されない() {
        var cnt = 0
        let counter = { ++cnt }
        
        self.wait { done in
            
            let p1 = Future.resolve(100)
            
            p1.map({ lhs -> String in
                done()
                return "\(lhs) \(counter()) to string"
            })
            
            dispatch_after(when(0.1), dispatch_get_main_queue()) {
                done()
            }
            
            return {
                XCTAssertEqual(0, cnt, "")
            }
        }
    }
    
    func test_thenの返り値がPromiseの場合() {
        var cnt = 0
        let counter = { ++cnt }
        
        self.wait { done in
            
            let p1 = Future.resolve(100)
            
            let p2 = p1.map({ lhs in
                Future.resolve("\(lhs) \(counter()) to string")
            })
            
            p2.eval({ _ in
                done()
            })
            
            return {
                XCTAssertEqual(1, cnt, "")
            }
        }
    }
    
    func test_rejectの動作() {
        var cnt = 0
        let counter = { ++cnt }
        
        self.wait { done in
            
            let p1 = Future<Int>.reject(NSError(domain: "hoge", code: 100, userInfo: nil))
            
            let p2 = p1.map({ lhs in
                Future.resolve("\(lhs) \(counter()) to string")
            }).recover({ e in
                Future.resolve("resolve \(e.domain)")
            })
            
            
            p2.eval({ ret in
                done()
                XCTAssertEqual(ret, "resolve hoge", "")
            }).fail({ e in
                
            })
            
            return {
                XCTAssertEqual(0, cnt, "")
            }
        }
    }
    
    func test_rejectの動作_catchしなければevalで受け取る() {
        var cnt = 0
        let counter = { ++cnt }
        
        self.wait { done in
            
            let p1 = Future<Int>.reject(NSError(domain: "hoge", code: 100, userInfo: nil))
            
            let p2 = p1.map({ lhs in
                Future.resolve("\(lhs) \(counter()) to string")
            })
            
            
            p2.eval({ ret in
                XCTAssertNil(ret, "")
            })
            
            p2.fail({ e in
                XCTAssertEqual(e.domain, "hoge", "")
                done()
            })
            
            return {
                XCTAssertEqual(0, cnt, "")
            }
        }
    }
    
    func test_zip_順次の処理だとタイムアウトになる２つの処理が並列に実行される() {
        var cnt = 0
        let counter = { ++cnt }
        
        self.wait { done in
            
            let u = Future { deferred in
                dispatch_after(when(0.8), dispatch_get_main_queue()) {
                    deferred.resolve(100)
                }
            }
            
            
            let v = Future { deferred in
                dispatch_after(when(0.8), dispatch_get_main_queue()) {
                    deferred.resolve("future v")
                }
            }
            
            zip(u, v).eval({ lhs in
                done()
                counter()
                XCTAssertEqual(lhs.0, 100, "")
                XCTAssertEqual(lhs.1, "future v", "")
            })
            
            return {
                XCTAssertEqual(1, cnt, "")
            }
        }
    }
    
    func test_zip_片方が失敗した場合はそこで次の処理に入る() {
        var cnt = 0
        let counter = { ++cnt }
        
        self.wait { done in
            
            let u = Future<Int> { deferred in
                dispatch_after(when(0.8), dispatch_get_main_queue()) {
                    deferred.reject(NSError(domain: "", code: 100, userInfo: nil))
                }
            }
            
            
            let v = Future { deferred in
                dispatch_after(when(2), dispatch_get_main_queue()) {
                    deferred.resolve("future v")
                }
            }
            
            zip(u, v).eval({ (u, v) in
                done()
                counter()
                XCTAssertEqual(u, 100, "")
                XCTAssertEqual(v, "future v", "")
            }).fail({ e in
                done()
                XCTAssertEqual(e.code, 100, "")
            })
            
            return {
                XCTAssertEqual(0, cnt, "")
            }
        }
    }
    
    func test_zip_順次の処理だとタイムアウトになる３つの処理が並列に実行される() {
        var cnt = 0
        let counter = { ++cnt }
        
        self.wait { done in
            
            let u = Future { deferred in
                dispatch_after(when(0.8), dispatch_get_main_queue()) {
                    deferred.resolve(100)
                }
            }
            
            
            let v = Future { deferred in
                dispatch_after(when(0.8), dispatch_get_main_queue()) {
                    deferred.resolve("future v")
                }
            }
            
            let w = Future { deferred in
                dispatch_after(when(0.8), dispatch_get_main_queue()) {
                    deferred.resolve(10.0)
                }
            }
            
            zip(u, v, w).eval({ (u, v, w) in
                done()
                counter()
                XCTAssertEqual(u, 100, "")
                XCTAssertEqual(v, "future v", "")
                XCTAssertEqual(w, 10.0, "")
            })
            
            return {
                XCTAssertEqual(1, cnt, "")
            }
        }
    }
    
    func test_zip_Array版() {
        
        self.wait { done in
            
            let fs = [
                Future.resolve(1),
                Future.resolve(10),
                Future.resolve(100),
                Future.resolve(1000),
            ]
            
            zip(fs, take: 4).eval({ lhs in
                
                XCTAssertEqual(lhs.count, 4, "")
                done()
            })
         
            return {
                
            }
        }
    }
}

let when = { sec in dispatch_time(DISPATCH_TIME_NOW, Int64(sec * Double(NSEC_PER_SEC))) }
extension XCTestCase {
    
    typealias DoneStatement = () -> Void
    func wait(till num: Int = 1, message: String = __FUNCTION__, _ block: DoneStatement -> DoneStatement) {
        self.wait(till: num, message: message, timeout: 1, block)
        
    }
    func wait(till num: Int, message: String = __FUNCTION__, timeout: NSTimeInterval, _ block: DoneStatement -> DoneStatement) {
        
        let expectation = self.expectationWithDescription(message)
        let queue = dispatch_queue_create("XCTestCase.wait", nil)
        var living = num
        
        var completion: (() -> Void)!
        let done: DoneStatement = {
            dispatch_async(queue) { //シングルキューで必ず順番に処理する
                living--
                if living == 0 {
                    completion?()
                    expectation.fulfill()
                }
            }
        }
        
        completion = block(done)
        
        self.waitForExpectationsWithTimeout(timeout) { (error) -> Void in
            completion?()
            return
        }
    }
}
