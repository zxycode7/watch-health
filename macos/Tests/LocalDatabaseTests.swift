import XCTest
import SQLite3
@testable import Veyra

final class LocalDatabaseTests: XCTestCase {
    func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("health.sqlite3").path,&db),SQLITE_OK)
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE samples(type TEXT,id TEXT,start TEXT,end TEXT,value REAL,unit TEXT,source_name TEXT,source_bundle TEXT,device_model TEXT,metadata TEXT);
        CREATE TABLE devices(id TEXT,name TEXT,last_sync TEXT,revoked INTEGER,paired_at TEXT);
        INSERT INTO samples VALUES('sleep','overlap','2026-10-15T23:00:00.000000+00:00','2026-10-16T06:00:00.000000+00:00',3,'category','Watch','watch','Watch','{}');
        INSERT INTO samples VALUES('sleep','before','2026-10-15T22:00:00.000000+00:00','2026-10-16T00:00:00.000000+00:00',3,'category','Watch','watch','Watch','{}');
        INSERT INTO samples VALUES('steps','instant','2026-10-16T00:00:00.000000+00:00','2026-10-16T00:00:00.000000+00:00',4,'count','Phone','phone','iPhone','{}');
        INSERT INTO samples VALUES('steps','at-end','2026-10-17T00:00:00.000000+00:00','2026-10-17T00:00:00.000000+00:00',5,'count','Phone','phone','iPhone','{}');
        """
        XCTAssertEqual(sqlite3_exec(db,schema,nil,nil,nil),SQLITE_OK)
        return directory
    }
    func testOverlappingIntervalsAndHalfOpenBoundaries() async throws {
        let directory = try fixture(); defer { try? FileManager.default.removeItem(at:directory) }
        let db = LocalDatabase(directory:directory)
        let start = "2026-10-16T00:00:00+00:00".bridgeDate!; let end = "2026-10-17T00:00:00+00:00".bridgeDate!
        let sleep = try await db.page(metric:.sleep,start:start,end:end,source:"",offset:0)
        XCTAssertEqual(sleep.rows.map(\.id),["overlap"])
        let steps = try await db.page(metric:.steps,start:start,end:end,source:"",offset:0)
        XCTAssertEqual(steps.rows.map(\.id),["instant"])
        let injected = try await db.page(metric:.steps,start:start,end:end,source:"' OR 1=1 --",offset:0)
        XCTAssertEqual(injected.total,0)
        let snapshot = try await db.snapshot()
        XCTAssertEqual(snapshot.inventory.count,28)
        XCTAssertEqual(snapshot.inventory.reduce(0) { $0 + $1.count },4)
    }
    func testMissingDatabaseProducesRecoverableError() async throws {
        let db = LocalDatabase(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        do { _ = try await db.snapshot(); XCTFail("Missing store must not become an empty healthy database") }
        catch { XCTAssertTrue(error.localizedDescription.contains("尚未找到")) }
    }
    func testMalformedValueIsNotInventedAsZero() async throws {
        let directory = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("health.sqlite3").path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "UPDATE samples SET value='invalid' WHERE id='instant'", nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        let database = LocalDatabase(directory: directory)
        do {
            _ = try await database.page(metric: .steps, start: "2026-10-16T00:00:00+00:00".bridgeDate!, end: "2026-10-17T00:00:00+00:00".bridgeDate!, source: "", offset: 0)
            XCTFail("An unreadable value must not appear as zero")
        } catch { XCTAssertTrue(error.localizedDescription.contains("数值")) }
    }

    func testSubprocessCannotAddBytecodeToPackagedModules() async throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        try "x = 7\n".write(to: bundle.appendingPathComponent("immutable_payload.py"), atomically: true, encoding: .utf8)
        let data = try await DesktopModel.run("/usr/bin/env", ["python3", "-c", "import sys; sys.path.insert(0,sys.argv[1]); import immutable_payload; print(immutable_payload.x)", bundle.path])
        XCTAssertEqual(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), "7")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: bundle.path), ["immutable_payload.py"])
    }

}
