const std = @import("std");

fn Comparer(comptime t: type) type {
    return fn (a: t, b: t) std.math.Order;
}

fn Node(comptime DataType: type, comptime Cmp: Comparer(DataType)) type {
    return struct {
        const Self = @This();
        const comparer = Cmp;

        data: DataType,
        height: i32,
        left: ?*Self,
        right: ?*Self,

        fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            if (self.left) |left| left.deinit(allocator);
            if (self.right) |right| right.deinit(allocator);
            allocator.destroy(self);
        }

        fn getNodeHeight(node: ?*Self) i32 {
            return if (node) |n| n.height else 0;
        }

        fn setNodeHeight(self: *Self) void {
            self.height = @max(getNodeHeight(self.right), getNodeHeight(self.left)) + 1;
        }

        fn balanceFactor(self: *Self) i32 {
            return getNodeHeight(self.right) - getNodeHeight(self.left);
        }

        fn rotateLeft(self: *Self) *Self {
            const new_root = self.right.?;
            self.right = new_root.left;
            new_root.left = self;
            self.setNodeHeight();
            new_root.setNodeHeight();
            return new_root;
        }

        fn rotateRight(self: *Self) *Self {
            const new_root = self.left.?;
            self.left = new_root.right;
            new_root.right = self;
            self.setNodeHeight();
            new_root.setNodeHeight();
            return new_root;
        }

        fn rebalance(self: *Self) *Self {
            const bal = self.balanceFactor();

            if (bal < -1) {
                if (self.left.?.balanceFactor() > 0) {
                    self.left = self.left.?.rotateLeft();
                }
                return self.rotateRight();
            } else if (bal > 1) {
                if (self.right.?.balanceFactor() < 0) {
                    self.right = self.right.?.rotateRight();
                }
                return self.rotateLeft();
            }
            self.setNodeHeight();
            return self;
        }

        fn insert(self: *Self, new_node: *Self, allocator: std.mem.Allocator) *Self {
            switch (comparer(new_node.data, self.data)) {
                .gt => if (self.right) |right| {
                    self.right = right.insert(new_node, allocator);
                } else {
                    self.right = new_node;
                },
                .lt => if (self.left) |left| {
                    self.left = left.insert(new_node, allocator);
                } else {
                    self.left = new_node;
                },
                .eq => {
                    allocator.destroy(new_node);
                    return self;
                },
            }
            return self.rebalance();
        }

        const ExtractResult = struct { min: *Self, root: ?*Self };

        fn extractMin(self: *Self) ExtractResult {
            if (self.left) |left| {
                const result = left.extractMin();
                self.left = result.root;
                return .{ .min = result.min, .root = self.rebalance() };
            }
            // self IS the minimum — detach it and hand its right child up.
            return .{ .min = self, .root = self.right };
        }

        fn delete(self: ?*Self, allocator: std.mem.Allocator, value: DataType) ?*Self {
            const node = self orelse return null;

            switch (comparer(value, node.data)) {
                .lt => node.left = delete(node.left, allocator, value),
                .gt => node.right = delete(node.right, allocator, value),
                .eq => {
                    if (node.left == null or node.right == null) {
                        const temp = if (node.left) |l| l else node.right;
                        allocator.destroy(node);
                        return temp;
                    } else {
                        const result = node.right.?.extractMin();
                        const successor = result.min;
                        successor.left = node.left;
                        successor.right = result.root;
                        allocator.destroy(node);
                        return successor.rebalance();
                    }
                },
            }
            return node.rebalance();
        }
    };
}

pub fn Tree(comptime DataType: type, comptime Cmp: Comparer(DataType)) type {
    return struct {
        const Self = @This();
        const TreeNode = Node(DataType, Cmp);

        root: ?*TreeNode = null,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            if (self.root) |root| {
                root.deinit(self.allocator);
            }
            self.root = null;
        }

        pub fn insert(self: *Self, value: DataType) !void {
            const new_node = try self.allocator.create(TreeNode);
            new_node.* = .{
                .data = value,
                .height = 1,
                .left = null,
                .right = null,
            };
            self.root = if (self.root) |r| r.insert(new_node, self.allocator) else new_node;
        }

        pub fn delete(self: *Self, value: DataType) void {
            self.root = TreeNode.delete(self.root, self.allocator, value);
        }
    };
}

fn Cmpi32(x: i32, y: i32) std.math.Order {
    return std.math.order(x, y);
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const testTimes: usize = 100_000;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const I32Tree = Tree(i32, Cmpi32);
    var tree = I32Tree.init(allocator);
    // Note: We manually delete nodes, but this cleans up the root if anything remains.
    defer tree.deinit();

    // Allocate timings on the HEAP to avoid Stack Overflow
    const timings = try allocator.alloc(f64, testTimes);
    defer allocator.free(timings);

    try stdout.print("Running benchmark for {} items...\n", .{testTimes});

    const asc_f64 = struct {
        fn lessThan(_: void, a: f64, b: f64) bool {
            return a < b;
        }
    }.lessThan;

    // Insertion benchmark
    var i: usize = 0;
    var total_ns: f64 = 0;
    while (i < testTimes) : (i += 1) {
        const start = try std.time.Instant.now();
        try tree.insert(@intCast(i));
        const end = try std.time.Instant.now();
        timings[i] = @as(f64, @floatFromInt(end.since(start)));
        total_ns += timings[i];
    }
    std.mem.sort(f64, timings, {}, asc_f64);
    try stdout.print("Insertion — mean: {d:.2}ns  median: {d:.2}ns  p99: {d:.2}ns\n", .{
        total_ns / @as(f64, @floatFromInt(testTimes)),
        timings[testTimes / 2],
        timings[testTimes * 99 / 100],
    });

    // Deletion benchmark
    i = 0;
    total_ns = 0;
    while (i < testTimes) : (i += 1) {
        const start = try std.time.Instant.now();
        tree.delete(@intCast(i));
        const end = try std.time.Instant.now();
        timings[i] = @as(f64, @floatFromInt(end.since(start)));
        total_ns += timings[i];
    }
    std.mem.sort(f64, timings, {}, asc_f64);
    try stdout.print("Deletion  — mean: {d:.2}ns  median: {d:.2}ns  p99: {d:.2}ns\n", .{
        total_ns / @as(f64, @floatFromInt(testTimes)),
        timings[testTimes / 2],
        timings[testTimes * 99 / 100],
    });
}

test "simple insert rebalance" {
    const allocator = std.testing.allocator;

    const i32Tree = Tree(i32, Cmpi32);
    var tree = i32Tree.init(allocator);
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
    const allocator = std.testing.allocator;

    const i32Tree = Tree(i32, Cmpi32);
    var tree = i32Tree.init(allocator);
    defer tree.deinit();

    try tree.insert(2);
    try tree.insert(1);
    try tree.insert(3);
    try tree.insert(4);
    try tree.insert(5);
    tree.delete(4);
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

test "duplicate insert does not grow tree" {
    const allocator = std.testing.allocator;

    const i32Tree = Tree(i32, Cmpi32);
    var tree = i32Tree.init(allocator);
    defer tree.deinit();

    try tree.insert(1);
    try tree.insert(2);
    try tree.insert(2); // duplicate — should be a no-op
    try tree.insert(3);

    // Tree should look like a balanced tree of {1,2,3}, not have a duplicate 2.
    try std.testing.expectEqual(@as(i32, 2), tree.root.?.data);
    try std.testing.expectEqual(@as(i32, 1), tree.root.?.left.?.data);
    try std.testing.expectEqual(@as(i32, 3), tree.root.?.right.?.data);
    try std.testing.expectEqual(null, tree.root.?.left.?.left);
    try std.testing.expectEqual(null, tree.root.?.left.?.right);
    try std.testing.expectEqual(null, tree.root.?.right.?.left);
    try std.testing.expectEqual(null, tree.root.?.right.?.right);
}
