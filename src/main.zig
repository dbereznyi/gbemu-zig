const std = @import("std");
const Gb = @import("gameboy/gameboy.zig").Gb;
const Sdl = @import("sdl.zig").Sdl;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            @panic("leak detected");
        }
    }
    const alloc_gpa = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        try std.io.getStdErr().writer().print("Usage: {s} <path to ROM file>\n", .{args[0]});
        std.process.exit(1);
    }

    const rom_filepath = args[1];
    const dirname = std.fs.path.dirname(rom_filepath) orelse "";
    const rom_filepath_noext = try std.fmt.allocPrint(
        alloc,
        "{s}{c}{s}",
        .{ dirname, std.fs.path.sep, std.fs.path.stem(rom_filepath) },
    );
    defer alloc.free(rom_filepath_noext);
    const save_data_filepath = try std.fmt.allocPrint(
        alloc,
        "{s}.sav",
        .{rom_filepath_noext},
    );
    defer alloc.free(save_data_filepath);

    const rom = try std.fs.cwd().readFileAlloc(alloc, rom_filepath, 1024 * 1024 * 1024);
    defer alloc.free(rom);

    const save_data: ?[]u8 = read_save_data: {
        const data = std.fs.cwd().readFileAlloc(alloc, save_data_filepath, 128 * 1024) catch |err| switch (err) {
            error.FileNotFound => break :read_save_data null,
            else => {
                std.log.warn("Failed to read save data: {}\n", .{err});
                break :read_save_data null;
            },
        };
        break :read_save_data data;
    };
    defer if (save_data) |data| alloc.free(data);

    var gb = try Gb.init(
        alloc,
        rom,
        save_data,
    );
    defer gb.deinit(alloc);

    var sdl = try Sdl.init(alloc_gpa, rom_filepath_noext, &gb);
    defer sdl.deinit(alloc_gpa);

    gb.setVblankCallback(.{
        .context = @ptrCast(&sdl),
        .callback = @ptrCast(&Sdl.vblankCallback),
    });
    gb.setAudioCallback(.{
        .context = @ptrCast(&sdl),
        .callback = @ptrCast(&Sdl.audioCallback),
    });

    try sdl.run();

    try gb.cart.persistRam(save_data_filepath);
}
