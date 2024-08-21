const std = @import("std");

const max_i32 = std.math.maxInt(i32);
const min_i32 = std.math.minInt(i32);

fn Comparer(t: type) type {
    return fn (a: t, b: t) std.math.Order;
}

fn Node(comptime DataType: type, comptime Cmp: Comparer(DataType)) type {
    return struct {
        const Self = @This();
        const comparer = Cmp;

        fn getNodeHeight(node: ?*Self) i32 {
            return if (node) |n| n.height else 0;
        }

        fn setNodeHeight(node: *Self) void {
            node.height = @max(getNodeHeight(node.right), getNodeHeight(node.left)) + 1;
        }

        data: DataType,
        height: i32,
        left: ?*Self,
        right: ?*Self,

        fn insert(self: *Self, new_node: *Self) *Self {
            const cmp = comparer(new_node.data, self.data);
            if (cmp.compare(.gt)) {
                if (self.right) |right| {
                    self.right = right.insert(new_node);
                } else {
                    self.right = new_node;
                }
            } else {
                if (self.left) |left| {
                    self.left = left.insert(new_node);
                } else {
                    self.left = new_node;
                }
            }
            setNodeHeight(self);
            return self.rebalance() catch self;
        }

        fn popMinNode(self: *Self) *Self {
            if (self.left) |l| {
                if (l.left == null) {
                    self.left = l.right;
                    l.right = null;
                    setNodeHeight(self);
                    return l;
                } else {
                    const out = l.left.?.popMinNode();
                    setNodeHeight(self);
                    return out;
                }
            }
            return self;
        }
        fn popMaxNode(self: *Self) *Self {
            if (self.right) |r| {
                if (r.right == null) {
                    self.right = r.left;
                    r.left = null;
                    setNodeHeight(self);
                    return r;
                } else {
                    const out = popMaxNode(r.right.?);
                    setNodeHeight(self);
                    return out;
                }
                self.right = r.left;
                return r;
            }
            return self;
        }

        fn delete(self: *Self, allocator: *std.mem.Allocator, value: i32) ?*Self {
            const cmp = comparer(value, self.data);
            if (cmp.compare(.eq)) {
                var new_root: ?*Self = null;
                if (self.left != null or self.right != null) {
                    if (self.left == null) {
                        new_root = self.right;
                        setNodeHeight(new_root.?);
                    } else if (self.right == null) {
                        new_root = self.left;
                        setNodeHeight(new_root.?);
                    } else {
                        new_root = self.right.?.popMinNode();
                        new_root.?.left = self.left;
                        setNodeHeight(new_root.?);
                        new_root = new_root.?.rebalance() catch unreachable;
                    }
                }
                allocator.destroy(self);
                return new_root;
            }

            if (cmp.compare(.gt)) {
                if (self.right) |r| {
                    self.right = r.delete(allocator, value);
                }
            } else {
                if (self.left) |l| {
                    self.left = l.delete(allocator, value);
                }
            }
            setNodeHeight(self);
            return self.rebalance() catch unreachable;
        }

        fn balance(self: *Self) i32 {
            return getNodeHeight(self.right) - getNodeHeight(self.left);
        }

        fn rotateLeft(self: *Self) anyerror!*Self {
            var new_root = self.right.?;
            self.right = new_root.left;
            new_root.left = self;
            setNodeHeight(self);
            setNodeHeight(new_root);
            return new_root;
        }
        fn rotateRight(self: *Self) anyerror!*Self {
            var new_root = self.left.?;
            self.left = new_root.right;
            new_root.right = self;
            setNodeHeight(self);
            setNodeHeight(new_root);
            return new_root;
        }
        fn rotateLeftRight(self: *Self) anyerror!*Self {
            self.left = try self.left.?.rotateLeft();
            return try self.rotateRight();
        }
        fn rotateRightLeft(self: *Self) anyerror!*Self {
            self.right = try self.right.?.rotateRight();
            return try self.rotateLeft();
        }
        fn rebalance(self: *Self) anyerror!*Self {
            const bal = self.balance();
            if (bal >= -1 and bal <= 1) {
                return self;
            }
            const lBal = if (self.left) |l| l.balance() else 0;
            const rBal = if (self.right) |r| r.balance() else 0;
            if (bal < -1 and lBal <= -1) {
                return try self.rotateRight();
            } else if (bal < -1 and lBal >= 1) {
                return try self.rotateLeftRight();
            } else if (bal > 1 and rBal <= -1) {
                return try self.rotateRightLeft();
            } else if (bal > 1 and rBal >= 1) {
                return try self.rotateLeft();
            }
            return self;
        }
    };
}

fn Tree(comptime DataType: type, comptime Cmp: Comparer(DataType)) type {
    return struct {
        const Self = @This();
        const TreeNode = Node(DataType, Cmp);

        root: ?*TreeNode,
        allocator: *std.heap.ArenaAllocator,

        fn init(allocator: *std.heap.ArenaAllocator) Self {
            return Self{
                .root = null,
                .allocator = allocator,
            };
        }

        fn deinit(self: Self) void {
            self.allocator.deinit();
        }

        pub fn insert(self: *Self, value: DataType) anyerror!void {
            const new_node = try self.allocator.allocator().create(TreeNode);
            new_node.* = .{
                .data = value,
                .height = 1,
                .left = null,
                .right = null,
            };
            if (self.root == null) {
                self.root = new_node;
                return;
            }
            self.root = self.root.?.insert(new_node);
        }
        pub fn delete(self: *Self, value: DataType) anyerror!void {
            var alloc = self.allocator.allocator();
            self.root = self.root.?.delete(&alloc, value);
        }

        pub fn rebalance(self: *Self) anyerror!void {
            self.root = try self.root.?.rebalance();
        }

        pub fn print(self: Self, writer: anytype) anyerror!void {
            //bfs for the win
            var nodes = std.fifo.LinearFifo(*TreeNode, .Dynamic).init(self.allocator.allocator());
            defer nodes.deinit();
            try nodes.writeItem(self.root.?);
            while (nodes.count > 0) {
                const curr_node = nodes.readItem().?;
                try writer.print("[{},{}], ", .{ curr_node.data, curr_node.height });
                if (curr_node.left) |l| {
                    try nodes.writeItem(l);
                }
                if (curr_node.right) |r| {
                    try nodes.writeItem(r);
                }
            }

            try writer.print("\n", .{});
        }
    };
}

fn Cmpi32(x: i32, y: i32) std.math.Order {
    return std.math.order(x, y);
}

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    const testTimes: i64 = 1_000_000;
    // const testTimes: i64 = 1_000;
    const testTimesFloat: f64 = @floatFromInt(testTimes);
    var meanTime: f64 = 0;
    var standardDeviation: f64 = 0;

    const stdout = std.io.getStdOut().writer();

    try stdout.print("Test with {} insertion and deletions\n", .{testTimes});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const i32Tree = Tree(i32, Cmpi32);
    var tree = i32Tree.init(&arena);
    defer tree.deinit();

    // init timestamps array and index
    var timings = [_]f64{0} ** testTimes;
    var i: usize = 0;

    // inserting test
    while (i < testTimes) {
        const start = try std.time.Instant.now();
        try tree.insert(@intCast(i));
        const end = try std.time.Instant.now();
        timings[i] = @floatFromInt(end.since(start));
        meanTime += (timings[i] / testTimes);
        i += 1;
    }
    i = 0;
    while (i < testTimes) {
        standardDeviation += std.math.pow(f64, (meanTime - timings[i]), 2);
        i += 1;
    }
    standardDeviation = std.math.sqrt(standardDeviation / (testTimes - 1));
    try stdout.print("Insertion\nmean={d:.4}ns, deviation={d:.4}ns\n", .{ meanTime, standardDeviation });
    try stdout.print("first elements: [{d:.4}ns, {d:.4}ns]\n", .{ timings[0], timings[1] });
    try stdout.print("median elements: [{d:.4}ns, {d:.4}ns]\n", .{ timings[@floor(testTimesFloat / 2)], timings[@floor(testTimesFloat / 2) + 1] });
    try stdout.print("last elements: [{d:.4}ns, {d:.4}ns]\n", .{ timings[testTimes - 2], timings[testTimes - 1] });

    // init timestamps array and index
    timings = [_]f64{0} ** testTimes;
    standardDeviation = 0;
    meanTime = 0;
    i = 0;

    // deletion
    while (i < testTimes) {
        const start = try std.time.Instant.now();
        try tree.delete(@intCast(i));
        const end = try std.time.Instant.now();
        timings[i] = @floatFromInt(end.since(start));
        meanTime += timings[i];
        i += 1;
    }
    meanTime /= testTimes;
    i = 0;
    while (i < testTimes) {
        standardDeviation += std.math.pow(f64, (meanTime - timings[i]), 2);
        i += 1;
    }
    standardDeviation = std.math.sqrt(standardDeviation / (testTimes - 1));

    try stdout.print("Deletion\nmean={d:.4}ns, deviation={d:.4}ns\n", .{ meanTime, standardDeviation });
    try stdout.print("first elements: [{d:.4}ns, {d:.4}ns]\n", .{ timings[0], timings[1] });
    try stdout.print("median elements: [{d:.4}ns, {d:.4}ns]\n", .{ timings[@floor(testTimesFloat / 2)], timings[@floor(testTimesFloat / 2) + 1] });
    try stdout.print("last elements: [{d:.4}ns, {d:.4}ns]\n", .{ timings[testTimes - 2], timings[testTimes - 1] });
}

test "simple insert rebalance" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const i32Tree = Tree(i32, Cmpi32);
    var tree = i32Tree.init(&arena);
    defer tree.deinit();
    try tree.insert(2);
    try tree.insert(1);
    try tree.insert(3);
    try tree.insert(4);
    try tree.insert(5);
    var node = tree.root;
    try std.testing.expectEqual(@as(i32, 2), node.?.data);
    node = tree.root.?.left;
    try std.testing.expectEqual(@as(i32, 1), node.?.data);
    node = node.?.right;
    try std.testing.expectEqual(null, node);
    const node_r = tree.root.?.right;
    try std.testing.expectEqual(@as(i32, 4), node_r.?.data);
    node = node_r.?.left;
    try std.testing.expectEqual(@as(i32, 3), node.?.data);
    node = node_r.?.right;
    try std.testing.expectEqual(@as(i32, 5), node.?.data);
}

test "simple delete rebalance" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const i32Tree = Tree(i32, Cmpi32);
    var tree = i32Tree.init(&arena);
    defer tree.deinit();
    try tree.insert(2);
    try tree.insert(1);
    try tree.insert(3);
    try tree.insert(4);
    try tree.insert(5);
    try tree.delete(4);
    var node = tree.root;
    try std.testing.expectEqual(@as(i32, 2), node.?.data);
    node = tree.root.?.left;
    try std.testing.expectEqual(@as(i32, 1), node.?.data);
    node = node.?.right;
    try std.testing.expectEqual(null, node);
    const node_r = tree.root.?.right;
    try std.testing.expectEqual(@as(i32, 5), node_r.?.data);
    node = node_r.?.left;
    try std.testing.expectEqual(@as(i32, 3), node.?.data);
    node = node_r.?.right;
    try std.testing.expectEqual(null, node);
}
