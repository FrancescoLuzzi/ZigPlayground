const std = @import("std");

fn Comparer(t: type) type {
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
            self.setNodeHeight();
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
            return self;
        }

        fn insert(self: *Self, new_node: *Self) *Self {
            switch (comparer(new_node.data, self.data)) {
                .gt => if (self.right) |right| {
                    self.right = right.insert(new_node);
                } else {
                    self.right = new_node;
                },
                else => if (self.left) |left| {
                    self.left = left.insert(new_node);
                } else {
                    self.left = new_node;
                },
            }
            return self.rebalance();
        }

        fn deleteMinAndReturnRightChild(self: *Self, allocator: std.mem.Allocator, out_min_data: *DataType) ?*Self {
            if (self.left) |left| {
                self.left = left.deleteMinAndReturnRightChild(allocator, out_min_data);
                return self.rebalance();
            }

            out_min_data.* = self.data;
            const right_child = self.right;
            allocator.destroy(self);
            return right_child;
        }

        fn delete(self: ?*Self, allocator: std.mem.Allocator, value: DataType) ?*Self {
            const node = self orelse return null;

            switch (comparer(value, node.data)) {
                .lt => node.left = delete(node.left, allocator, value),
                .gt => node.right = delete(node.right, allocator, value),
                .eq => {
                    // when we find the node that has a least one of it's children null (aka at the end of the tree)
                    // we return the non null child, if present, and deallocate the current node
                    // if the node has both the children (aka in the middle of the tree)
                    // we take the smallest value of the right sub tree,
                    // copy the value in the current node, this can be done because of the properties of the tree:
                    // the smallest value of the right subtree will be smaller of the right value and bigger than the left one
                    // then delete the smallest value in the right subtree
                    if (node.left == null or node.right == null) {
                        const temp = if (node.left) |l| l else node.right;
                        allocator.destroy(node);
                        return temp;
                    } else {
                        node.right = node.right.?.deleteMinAndReturnRightChild(allocator, &node.data);
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
            // Set root to null to prevent double-frees or use-after-free
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
            self.root = if (self.root) |r| r.insert(new_node) else new_node;
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
    const testTimes: usize = 100_000; // Lowered for standard run, 1M is fine on heap

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const I32Tree = Tree(i32, Cmpi32);
    var tree = I32Tree.init(allocator);
    // Note: We manually delete nodes, but this cleans up the root if anything remains.

    // Allocate timings on the HEAP to avoid Stack Overflow
    const timings = try allocator.alloc(f64, testTimes);
    defer allocator.free(timings);

    try stdout.print("Running benchmark for {} items...\n", .{testTimes});

    // Insertion Benchmark
    var i: usize = 0;
    var total_ns: f64 = 0;
    while (i < testTimes) : (i += 1) {
        const start = try std.time.Instant.now();
        try tree.insert(@intCast(i));
        const end = try std.time.Instant.now();

        const duration = @as(f64, @floatFromInt(end.since(start)));
        timings[i] = duration;
        total_ns += duration;
    }
    try stdout.print("Mean Insertion: {d:.2}ns\n", .{total_ns / @as(f64, @floatFromInt(testTimes))});

    // Deletion Benchmark
    i = 0;
    total_ns = 0;
    while (i < testTimes) : (i += 1) {
        const start = try std.time.Instant.now();
        tree.delete(@intCast(i));
        const end = try std.time.Instant.now();

        const duration = @as(f64, @floatFromInt(end.since(start)));
        total_ns += duration;
    }
    try stdout.print("Mean Deletion:  {d:.2}ns\n", .{total_ns / @as(f64, @floatFromInt(testTimes))});
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
