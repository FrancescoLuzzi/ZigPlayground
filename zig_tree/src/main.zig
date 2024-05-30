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
        return self;
    }

    fn delete(self: *Node, allocator: *std.mem.Allocator, value: i32) ?*Node {
        if (self.data == value) {
            var new_root = self.left;
            if (new_root) |l| {
                l.right = self.right;
            } else {
                new_root = self.right;
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
        return self;
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
        new_root.left = self;
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

const leftArrow = "/";
const rightArrow = "\\";
const spaceOrizzontal = " ";
const spaceVertical = "\n";

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
        try self.rebalance();
    }
    pub fn delete(self: *Tree, value: i32) anyerror!void {
        var alloc = self.allocator.allocator();
        self.root = self.root.?.delete(&alloc, value);
        try self.rebalance();
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
            try writer.print("[{}], ", .{curr_node.data});
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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    var tree = Tree.init(&arena);
    defer tree.deinit();

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout = std.io.getStdOut().writer();

    try tree.insert(10);
    try tree.insert(11);
    try tree.insert(7);
    try tree.insert(12);
    try tree.insert(9);
    try tree.insert(15);
    try tree.insert(8);
    try tree.print(stdout);
    try tree.insert(16);
    try tree.insert(17);
    try tree.print(stdout);
    try tree.delete(11);
    try tree.print(stdout);
}

test "simple test" {
    const arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var tree = Tree.init(arena);
    defer tree.deinit();
    try tree.insert(2);
    try tree.insert(1);
    try tree.insert(3);
    try tree.insert(4);
    try tree.insert(5);
    var node = tree.root;
    try std.testing.expectEqual(@as(i32, 3), node.?.data);
    node = tree.root.?.left;
    try std.testing.expectEqual(@as(i32, 2), node.?.data);
    node = node.?.right;
    try std.testing.expectEqual(null, node);
    node = tree.root.?.left;
    try std.testing.expectEqual(@as(i32, 2), node.?.data);
}
