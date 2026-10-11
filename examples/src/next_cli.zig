const std = @import("std");
const xarp = @import("xarp_zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const argv = try init.minimal.args.toSlice(gpa);
    defer gpa.free(argv);
    var next_cli = xarp.Xarp.new(gpa, "next_cli").withVersion("0.1.0").withAbout("About");
    defer next_cli.deinit();

    try next_cli.addArg(xarp.Arg.new("print").withHelp("prints hello").withShort('p').withLong("print").withValueName("VAl").setRequired(true));

    var matches = try next_cli.getMatches(argv);
    matches.deinit();

    if (matches.getOneParsed(comptime T: type, id: []const u8)) |found| {
        const name, const sub_matches = found;
        _ = sub_matches;
        if (std.mem.eql(u8, name, "print")) {
            std.debug.print("{s}", .{matches.getOne("print") orelse return error.MissingPrintVal});
        }
    }
}
