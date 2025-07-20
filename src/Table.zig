const std = @import("std");
const StringObj = @import("object.zig").StringObj;
const Value = @import("value.zig").Value;

const MAX_LOAD_PERCENTAGE = 75;

const Table = @This();
const Error = std.mem.Allocator.Error;

// Invariant: entries.len == 0 or count+1 < entries.len.
// That is, storing one more item will not fill up the table.
// entries.len == 0 is an exception to avoid allocating
// if the table will never have any data.
// TODO: is that exception actually worth it?
// TODO: consider adding a size which counts the number of values (not tombstones)
count: usize,
entries: []Entry,
alloc: std.mem.Allocator,

const Entry = struct {
    key: ?*StringObj,
    value: Value,

    fn hasValue(self: Entry) bool {
        return self.key != null;
    }

    fn isTombstone(self: Entry) bool {
        return !self.hasValue() and !self.value.is(.nil);
    }

    fn isFree(self: Entry) bool {
        return !self.hasValue() and self.value.is(.nil);
    }

    fn setFree(self: *Entry) void {
        self.key = null;
        self.value = .nil;
    }

    fn setTombstone(self: *Entry) void {
        self.key = null;
        self.value = .{ .boolean = true };
    }

    fn set(self: *Entry, key: *StringObj, value: Value) void {
        self.key = key;
        self.value = value;
    }
};

pub fn init(alloc: std.mem.Allocator) Table {
    return Table{
        .count = 0,
        .entries = &[_]Entry{},
        .alloc = alloc,
    };
}

pub fn set(self: *Table, key: *StringObj, value: Value) Error!bool {
    try self.ensureSpaceToAdd();

    var entry = self._find(key);
    if (entry.isFree()) {
        self.count += 1;
    }

    const wasNew = !entry.hasValue();
    entry.set(key, value);
    return wasNew;
}

pub fn addAll(self: *Table, other: *Table) Error!void {
    // We could potentially make this more efficient by
    // ensuring we have space to add all of other's entries.
    // We don't know how many collisions there will be,
    // but we need to be at least as big as the other one.
    for (other.entries) |entry| {
        if (!entry.hasValue()) continue;
        _ = try self.set(entry.key.?, entry.value);
    }
}

pub fn get(self: *const Table, key: *StringObj, outValue: *Value) bool {
    if (self.count == 0) return false;

    const entry = self._find(key);
    if (!entry.hasValue()) return false;

    outValue.* = entry.value;
    return true;
}

// Make sure there is space to add a new entry while still maintaining
// at least one free space in the table.
fn ensureSpaceToAdd(self: *Table) Error!void {
    const capacity = self.entries.len;

    if (self.count + 1 < capacity) return;

    const newCapacity = if (capacity < 8) 8 else capacity * 2;
    try self.resize(newCapacity);
}

fn resize(self: *Table, newCapacity: usize) Error!void {
    std.debug.assert(self.count < newCapacity);

    const newEntries: []Entry = try self.alloc.alloc(Entry, newCapacity);
    for (newEntries) |*entry| {
        entry.setFree();
    }

    self.count = 0;
    for (self.entries) |entry| {
        if (!entry.hasValue()) continue;

        const dest = findByIdentity(self.count, newEntries, entry.key.?);
        // *dest = entry; ??
        dest.key = entry.key;
        dest.value = entry.value;
        self.count += 1;
    }

    self.alloc.free(self.entries);
    self.entries = newEntries;
}

fn _find(self: *const Table, key: *StringObj) *Entry {
    return findByIdentity(self.count, self.entries, key);
}

inline fn compareByIdentity(a: *StringObj, b: *StringObj) bool {
    return a == b;
}

fn findByIdentity(count: usize, entries: []Entry, key: *StringObj) *Entry {
    return find(count, entries, key, compareByIdentity);
}

inline fn compareByValue(a: *StringObj, b: *StringObj) bool {
    return std.mem.eql(u8, a.value, b.value);
}

fn findByValue(count: usize, entries: []Entry, key: *StringObj) *Entry {
    return find(count, entries, key, compareByValue);
}

fn find(count: usize, entries: []Entry, key: *StringObj, comptime CmpFunc: anytype) *Entry {
    // There must be at least one free space in the table
    // or this will not work.  Rely on the caller to tell us
    // the count, since we use this for both regular options
    // and resizing.
    std.debug.assert(count < entries.len);

    var index = key.hash % entries.len;
    var tombstone: ?*Entry = null;
    var checked: usize = 0;
    while (true) {
        const entry = &entries[index];
        if (entry.hasValue()) {
            if (CmpFunc(key, entry.key.?)) {
                return entry;
            }
            // else move to next slot
        } else if (entry.isTombstone()) {
            // remember first tombstone
            tombstone = tombstone orelse entry;
        } else {
            return tombstone orelse entry;
        }
        index = (index + 1) % entries.len;

        // prevent infinite loop, eg, if we somehow don't have any free slots:
        std.debug.assert(checked <= entries.len);
        checked += 1;
    }
}

fn delete(self: *Table, key: *StringObj) bool {
    if (self.count == 0) return false;

    const entry = self._find(key);
    if (entry.hasValue()) {
        entry.setTombstone();
        return true;
    }

    return false;
}

// This is to support testing, since our `count` member also counts tombstones.
fn countValues(self: *const Table) usize {
    var count: usize = 0;
    for (self.entries) |entry| {
        if (entry.hasValue()) count += 1;
    }
    return count;
}

fn dropContents(self: *Table) void {
    // TODO: can we be sure that the contents used the same allocator?
    // TODO: de-allocation of values
    // TODO: can we be used after this?
    // This is currently here to support testing, not sure if it's needed for
    // production code...
    for (self.entries) |entry| {
        if (entry.key == null) continue;
        entry.key.?.deinit(self.alloc);
    }
    self.count = 0;
}

pub fn deinit(self: *const Table) void {
    // seems safe even if we haven't allocated any entries??
    self.alloc.free(self.entries);
}

pub fn format(
    self: *const Table,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    try writer.print("table({}/{}/{}) {{\n", .{ self.countValues(), self.count, self.entries.len });
    for (self.entries, 0..) |entry, i| {
        if (entry.hasValue()) {
            try writer.print("  {}: {s}: {},\n", .{ i, entry.key.?.value, entry.value });
        } else if (entry.isTombstone()) {
            try writer.print("  {}: -- tombstone,\n", .{i});
        } else {
            try writer.print("  {}: -- free,\n", .{i});
        }
    }
    try writer.print("}}", .{});
}

const StringPool = struct {
    alloc: std.mem.Allocator,
    table: Table,

    pub fn init(allocator: std.mem.Allocator) StringPool {
        return StringPool{
            .alloc = allocator,
            .table = Table.init(allocator),
        };
    }

    pub fn intern(self: *StringPool, key: []const u8) !*StringObj {
        // possible optimisations:
        // - don't resize until we know we're going to add the new key
        //   - if we resize after finding out but before adding, we need to re-find
        //     because the entry will have moved
        //   - if we resize after adding, we'll have temporarily violated the
        //     invariant that count+1 < entries.len; but might be ok?
        // - don't allocate the new key until we know we're going to add it

        try self.table.ensureSpaceToAdd();

        const keyObj = try StringObj.init(self.alloc, key);
        const entry = findByValue(self.table.count, self.table.entries, keyObj);
        if (entry.hasValue()) {
            keyObj.deinit(self.alloc);
            return entry.key.?;
        }

        // we assume no tombstones here because we're not supporting deleting...
        self.table.count += 1;
        entry.set(keyObj, .nil);
        return keyObj;
    }

    pub fn deinit(self: *StringPool) void {
        self.table.dropContents();
        self.table.deinit();
    }
};

test "table" {
    var t = Table.init(std.testing.allocator);
    defer t.deinit();

    try std.testing.expectEqual(0, t.entries.len);
    try std.testing.expectEqual(0, t.count);

    const key = try StringObj.init(std.testing.allocator, "hello");
    defer key.deinit(std.testing.allocator);

    const isNew = try t.set(key, .{ .nil = {} });
    try std.testing.expect(isNew);
    try std.testing.expectEqual(1, t.count);

    var t2 = Table.init(std.testing.allocator);
    defer t2.deinit();
    try t2.addAll(&t);
    try std.testing.expectEqual(1, t2.count);
}

test "table get" {
    var t = Table.init(std.testing.allocator);
    defer t.deinit();

    const key = try StringObj.init(std.testing.allocator, "hello");
    defer key.deinit(std.testing.allocator);

    _ = try t.set(key, .{ .number = 1 });
    var outValue = Value.NIL;
    const found = t.get(key, &outValue);
    try std.testing.expect(found);
    try std.testing.expectEqual(Value{ .number = 1 }, outValue);

    const unknownKey = try StringObj.init(std.testing.allocator, "world");
    defer unknownKey.deinit(std.testing.allocator);
    const notFound = t.get(unknownKey, &outValue);
    try std.testing.expect(!notFound);
}

test "lookup in empty table" {
    var t = Table.init(std.testing.allocator);
    defer t.deinit();

    const key = try StringObj.init(std.testing.allocator, "hello");
    defer key.deinit(std.testing.allocator);

    var outValue = Value.NIL;
    const found = t.get(key, &outValue);
    try std.testing.expect(!found);
}

test "delete" {
    var t = Table.init(std.testing.allocator);
    defer t.deinit();

    const key = try StringObj.init(std.testing.allocator, "hello");
    defer key.deinit(std.testing.allocator);

    _ = try t.set(key, .{ .number = 1 });
    try std.testing.expectEqual(1, t.count);

    var outValue = Value.NIL;
    const found = t.get(key, &outValue);
    try std.testing.expect(found);
    try std.testing.expectEqual(Value{ .number = 1 }, outValue);

    const deleted = t.delete(key);
    try std.testing.expect(deleted);
    try std.testing.expectEqual(0, t.countValues());

    const redeleted = t.delete(key);
    try std.testing.expect(!redeleted);

    const notFound = t.get(key, &outValue);
    try std.testing.expect(!notFound);
}

fn expectSame(table: *const Table, stdMap: *std.StringHashMap(f64)) !void {
    try std.testing.expectEqual(stdMap.count(), table.countValues());

    for (table.entries) |entry| {
        if (entry.key == null) continue;
        const maybeVal = stdMap.get(entry.key.?.value);
        try std.testing.expect(maybeVal != null);
        const val = maybeVal.?;
        try std.testing.expectEqual(val, entry.value.number);
    }
}

test "compare to std map" {
    var keys = StringPool.init(std.testing.allocator);
    // This will track and free all our keys.
    // For values, we'll only use numbers, which don't require allocation.
    defer keys.deinit();

    var stdMap = std.StringHashMap(f64).init(std.testing.allocator);
    defer stdMap.deinit();

    var table = Table.init(std.testing.allocator);
    defer table.deinit();

    // empty:
    try expectSame(&table, &stdMap);

    // write in 100 entries:
    inline for (0..10) |i| {
        inline for (0..10) |j| {
            const key = "a" ** i ++ "b" ** j;
            const val = 1.0 * @as(f64, i * j);
            _ = try table.set(try keys.intern(key), .{ .number = val });
            try stdMap.put(key, val);
        }
    }
    try expectSame(&table, &stdMap);

    // overwrite some of those:
    inline for (0..10) |i| {
        if (i % 2 == 0) {
            continue;
        }
        inline for (1..10) |j| {
            if (j % 2 == 0) {
                continue;
            }
            const key = "a" ** i ++ "b" ** j;
            const val = 2.0 * @as(f64, i * j);
            _ = try table.set(try keys.intern(key), .{ .number = val });
            try stdMap.put(key, val);
        }
    }
    try expectSame(&table, &stdMap);

    // delete a bunch:
    inline for (0..10) |i| {
        if (i % 3 == 0) {
            continue;
        }
        inline for (0..10) |j| {
            if (j % 3 == 0) {
                continue;
            }
            const key = "a" ** i ++ "b" ** j;
            _ = table.delete(try keys.intern(key));
            _ = stdMap.remove(key);
        }
    }
    try expectSame(&table, &stdMap);

    // write in some more, to test writing over tombstones:
    inline for (0..10) |i| {
        if (i % 2 == 0) {
            continue;
        }
        inline for (1..10) |j| {
            if (j % 2 == 0) {
                continue;
            }
            const key = "a" ** i ++ "b" ** j;
            const val = 3.0 * @as(f64, i * j);
            const internedKey = try keys.intern(key);
            _ = try table.set(internedKey, .{ .number = val });
            try stdMap.put(key, val);
        }
    }
    try expectSame(&table, &stdMap);

    // write in some more, to test resizing with tombstones:
    inline for (10..20) |i| {
        inline for (10..20) |j| {
            const key = "a" ** i ++ "b" ** j;
            const val = 4.0 * @as(f64, i * j);
            const internedKey = try keys.intern(key);
            _ = try table.set(internedKey, .{ .number = val });
            try stdMap.put(key, val);
        }
    }
    try expectSame(&table, &stdMap);
}
