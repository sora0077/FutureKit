//
//  FutureKitTests.swift
//  FutureKitTests
//
//  Created by 林達也 on 2015/02/14.
//  Copyright (c) 2015年 林達也. All rights reserved.
//

import UIKit
import XCTest

class FutureKitTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
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
            })
            p3.eval({ lhs in
                done()
                XCTAssertEqual(lhs, "101 1 to string 2 to string", "")
            })
            XCTAssertEqual(0, cnt, "")
            
            return {
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
