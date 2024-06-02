const std = @import("std");

const max_i32 = std.math.maxInt(i32);
const min_i32 = std.math.minInt(i32);

fn getNodeHeight(node: ?*Node) i32 {
    return if (node) |n| n.height else 0;
}

fn setNodeHeight(node: *Node) void {
    node.height = @max(getNodeHeight(node.right), getNodeHeight(node.left)) + 1;
}

const Node = struct {
    data: i32,
    height: i32,
    left: ?*Node,
    right: ?*Node,

    fn insert(self: *Node, new_node: *Node) *Node {
        if (new_node.data > self.data) {
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

    fn popMinNode(self: *Node) *Node {
        if (self.left) |l| {
            if (l.left == null) {
                self.left = l.right;
                l.right = null;
                setNodeHeight(self);
                return l;
            } else {
                const out = popMinNode(l.left.?);
                setNodeHeight(self);
                return out;
            }
        }
        return self;
    }
    fn popMaxNode(self: *Node) *Node {
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

    fn delete(self: *Node, allocator: *std.mem.Allocator, value: i32) ?*Node {
        if (self.data == value) {
            var new_root: ?*Node = null;
            if (self.left != null or self.right != null) {
                if (self.left == null) {
                    new_root = self.right;
                    setNodeHeight(new_root.?);
                } else if (self.right == null) {
                    new_root = self.left;
                    setNodeHeight(new_root.?);
                } else {
                    new_root = popMinNode(self.right.?);
                    new_root.?.left = self.left;
                    setNodeHeight(new_root.?);
                    new_root = new_root.?.rebalance() catch unreachable;
                }
            }
            allocator.destroy(self);
            return new_root;
        }

        if (value > self.data) {
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

    fn balance(self: *Node) i32 {
        return getNodeHeight(self.right) - getNodeHeight(self.left);
    }

    fn rotateLeft(self: *Node) anyerror!*Node {
        var new_root = self.right.?;
        self.right = new_root.left;
        new_root.left = self;
        setNodeHeight(self);
        setNodeHeight(new_root);
        return new_root;
    }
    fn rotateRight(self: *Node) anyerror!*Node {
        var new_root = self.left.?;
        self.left = new_root.right;
        new_root.right = self;
        setNodeHeight(self);
        setNodeHeight(new_root);
        return new_root;
    }
    fn rotateLeftRight(self: *Node) anyerror!*Node {
        self.left = try self.left.?.rotateLeft();
        return try self.rotateRight();
    }
    fn rotateRightLeft(self: *Node) anyerror!*Node {
        self.right = try self.right.?.rotateRight();
        return try self.rotateLeft();
    }
    fn rebalance(self: *Node) anyerror!*Node {
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

const Tree = struct {
    root: ?*Node,
    allocator: *std.heap.ArenaAllocator,

    fn init(allocator: *std.heap.ArenaAllocator) Tree {
        return Tree{
            .root = null,
            .allocator = allocator,
        };
    }

    fn deinit(self: Tree) void {
        self.allocator.deinit();
    }

    pub fn insert(self: *Tree, value: i32) anyerror!void {
        const new_node = try self.allocator.allocator().create(Node);
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
    pub fn delete(self: *Tree, value: i32) anyerror!void {
        var alloc = self.allocator.allocator();
        self.root = self.root.?.delete(&alloc, value);
    }

    pub fn rebalance(self: *Tree) anyerror!void {
        self.root = try self.root.?.rebalance();
    }

    pub fn print(self: Tree, writer: anytype) anyerror!void {
        //bfs for the win
        var nodes = std.fifo.LinearFifo(*Node, .Dynamic).init(self.allocator.allocator());
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
    var tree = Tree.init(&arena);
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
    var tree = Tree.init(&arena);
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
    var tree = Tree.init(&arena);
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
