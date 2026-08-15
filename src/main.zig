const r4os = @import("r4os");

const AppApi = struct {
    sys: r4os.r4sys.Context,
    window: *r4os.Window,
};

const palette = r4os.gui.default_palette;
const display_bg: u32 = 0xFFFFFF;
const accent: u32 = 0x000080;
const scale: i64 = 1_000_000;
const max_display: usize = 24;
const scratch_capacity: usize = 128;

pub fn r4_app_main(contract: *r4os.App) i32 {
    var timers: [1]r4os.Timer = .{.{}};
    var window = contract.window(timers[0..]) orelse return r4os.abi.err_no_group;
    var ctx = AppApi{ .sys = contract.system(), .window = &window };
    var app = App{ .ctx = &ctx };
    app.init();
    return app.run();
}

const Operation = enum {
    none,
    add,
    sub,
    mul,
    div,
};

const ButtonKind = enum(u8) {
    none = 0,
    digit0,
    digit1,
    digit2,
    digit3,
    digit4,
    digit5,
    digit6,
    digit7,
    digit8,
    digit9,
    decimal,
    sign,
    add,
    sub,
    mul,
    div,
    percent,
    equals,
    clear,
    clear_entry,
    backspace,
};

const button_grid = [_][4]ButtonKind{
    .{ .backspace, .clear_entry, .clear, .percent },
    .{ .digit7, .digit8, .digit9, .div },
    .{ .digit4, .digit5, .digit6, .mul },
    .{ .digit1, .digit2, .digit3, .sub },
    .{ .sign, .digit0, .decimal, .add },
};

const App = struct {
    ctx: *AppApi,
    w: i32 = 242,
    h: i32 = 286,
    display: [max_display + 1]u8 = .{0} ** (max_display + 1),
    display_len: usize = 1,
    stored: i64 = 0,
    pending: Operation = .none,
    new_input: bool = true,
    has_error: bool = false,
    pressed: ButtonKind = .none,
    should_exit: bool = false,

    fn init(self: *App) void {
        self.setDisplay("0");
    }

    fn run(self: *App) i32 {
        return self.runHosted();
    }

    fn runHosted(self: *App) i32 {
        _ = self.ctx.window.setTitle("Calculator");
        _ = self.ctx.window.setMinimumSize(222, 266);
        self.updateMetrics();
        self.render();

        while (!self.ctx.sys.programShouldClose() and !self.should_exit) {
            var needs_render = false;
            switch (self.ctx.window.waitMessage(r4os.time_contract.timeoutForever())) {
                .message => |message| switch (message) {
                    .close => return 0,
                    .resize => {
                        self.updateMetrics();
                        needs_render = true;
                    },
                    .key => |key| {
                        if (self.handleKey(key.key)) needs_render = true;
                    },
                    .mouse => |mouse| switch (mouse.action) {
                        .down => {
                            const button = self.buttonAt(mouse.x, mouse.y);
                            if (button != .none) {
                                self.pressed = button;
                                needs_render = true;
                            }
                        },
                        .up => {
                            const button = self.buttonAt(mouse.x, mouse.y);
                            if (self.pressed != .none) {
                                if (button == self.pressed) self.press(button);
                                self.pressed = .none;
                                needs_render = true;
                            }
                        },
                        .move => if (self.pressed != .none) {
                            needs_render = true;
                        },
                    },
                    else => {},
                },
                .failure => |raw| return raw,
                .timed_out => {},
            }
            if (needs_render) self.render();
        }
        return 0;
    }

    fn updateMetrics(self: *App) void {
        const info = self.ctx.window.info() orelse return;
        self.w = clampI32(info.client_w, 222, 480);
        self.h = clampI32(info.client_h, 266, 520);
    }

    fn render(self: *App) void {
        var paint = switch (self.ctx.window.beginPaint()) {
            .paint => |value| value,
            .failure => return,
        };
        defer paint.discard();
        const canvas = paint.canvas;
        var scratch: [scratch_capacity]u8 = .{0} ** scratch_capacity;
        _ = canvas.clear(palette.face);

        _ = canvas.text(10, 8, "R4OS Calculator", accent, palette.face);
        self.drawDisplay(canvas, scratch[0..]);
        self.drawButtons(canvas, scratch[0..]);
        _ = paint.present();
    }

    fn drawDisplay(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const rect = self.displayRect();
        drawSunken(canvas, rect);
        const inner = rect.inset(3, 3);
        _ = canvas.rect(inner, display_bg);
        _ = canvas.label(.{
            .rect = inner.inset(4, 5),
            .text = self.displayText(),
            .alignment = .right,
            .fg = palette.text,
            .bg = display_bg,
        }, scratch);
    }

    fn drawButtons(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        var row: usize = 0;
        while (row < button_grid.len) : (row += 1) {
            var col: usize = 0;
            while (col < button_grid[row].len) : (col += 1) {
                const kind = button_grid[row][col];
                _ = canvas.button(.{
                    .rect = self.buttonRect(row, col),
                    .text = buttonLabel(kind),
                    .state = if (self.pressed == kind) .pressed else .normal,
                    .is_default = kind == .equals,
                }, scratch);
            }
        }
        _ = canvas.button(.{
            .rect = self.equalsRect(),
            .text = "=",
            .state = if (self.pressed == .equals) .pressed else .normal,
            .is_default = true,
        }, scratch);
    }

    fn handleKey(self: *App, key: u8) bool {
        const kind = buttonForKey(key);
        if (kind == .none) return false;
        self.press(kind);
        return true;
    }

    fn press(self: *App, kind: ButtonKind) void {
        switch (kind) {
            .digit0 => self.inputDigit(0),
            .digit1 => self.inputDigit(1),
            .digit2 => self.inputDigit(2),
            .digit3 => self.inputDigit(3),
            .digit4 => self.inputDigit(4),
            .digit5 => self.inputDigit(5),
            .digit6 => self.inputDigit(6),
            .digit7 => self.inputDigit(7),
            .digit8 => self.inputDigit(8),
            .digit9 => self.inputDigit(9),
            .decimal => self.inputDecimal(),
            .sign => self.toggleSign(),
            .add => self.chooseOperation(.add),
            .sub => self.chooseOperation(.sub),
            .mul => self.chooseOperation(.mul),
            .div => self.chooseOperation(.div),
            .percent => self.percent(),
            .equals => self.equals(),
            .clear => self.clearAll(),
            .clear_entry => self.clearEntry(),
            .backspace => self.backspace(),
            .none => {},
        }
    }

    fn inputDigit(self: *App, digit: u8) void {
        if (self.has_error) self.clearAll();
        if (self.new_input) {
            self.setDisplay("0");
            self.new_input = false;
        }

        const ch: u8 = '0' + digit;
        if (self.display_len == 1 and self.display[0] == '0') {
            self.display[0] = ch;
            return;
        }
        if (self.display_len == 2 and self.display[0] == '-' and self.display[1] == '0') {
            self.display[1] = ch;
            return;
        }
        self.appendDisplayByte(ch);
    }

    fn inputDecimal(self: *App) void {
        if (self.has_error) self.clearAll();
        if (self.new_input) {
            self.setDisplay("0");
            self.new_input = false;
        }
        if (!self.displayContains('.')) self.appendDisplayByte('.');
    }

    fn toggleSign(self: *App) void {
        if (self.has_error) {
            self.clearAll();
            return;
        }
        if (self.isZeroDisplay()) return;
        if (self.display_len > 0 and self.display[0] == '-') {
            var i: usize = 0;
            while (i + 1 < self.display_len) : (i += 1) self.display[i] = self.display[i + 1];
            self.display_len -= 1;
            self.display[self.display_len] = 0;
            return;
        }
        if (self.display_len >= max_display) return;
        var i = self.display_len;
        while (i > 0) : (i -= 1) self.display[i] = self.display[i - 1];
        self.display[0] = '-';
        self.display_len += 1;
        self.display[self.display_len] = 0;
    }

    fn backspace(self: *App) void {
        if (self.has_error) {
            self.clearEntry();
            return;
        }
        if (self.new_input or self.display_len <= 1) {
            self.setDisplay("0");
            self.new_input = true;
            return;
        }
        self.display_len -= 1;
        self.display[self.display_len] = 0;
        if (self.display_len == 1 and self.display[0] == '-') self.setDisplay("0");
    }

    fn clearEntry(self: *App) void {
        self.has_error = false;
        self.new_input = true;
        self.setDisplay("0");
    }

    fn clearAll(self: *App) void {
        self.stored = 0;
        self.pending = .none;
        self.has_error = false;
        self.new_input = true;
        self.setDisplay("0");
    }

    fn percent(self: *App) void {
        const value = self.parseDisplay() orelse {
            self.setError();
            return;
        };
        self.setDisplayScaled(@divTrunc(value, 100));
        self.new_input = true;
    }

    fn chooseOperation(self: *App, op: Operation) void {
        if (self.has_error) {
            self.clearAll();
            return;
        }
        const value = self.parseDisplay() orelse {
            self.setError();
            return;
        };
        if (self.pending != .none and !self.new_input) {
            const result = self.applyPending(value) orelse {
                self.setError();
                return;
            };
            self.stored = result;
            self.setDisplayScaled(result);
        } else {
            self.stored = value;
        }
        self.pending = op;
        self.new_input = true;
    }

    fn equals(self: *App) void {
        if (self.has_error or self.pending == .none) return;
        const value = self.parseDisplay() orelse {
            self.setError();
            return;
        };
        const result = self.applyPending(value) orelse {
            self.setError();
            return;
        };
        self.stored = result;
        self.pending = .none;
        self.new_input = true;
        self.setDisplayScaled(result);
    }

    fn applyPending(self: *const App, rhs: i64) ?i64 {
        const lhs = self.stored;
        const result: i128 = switch (self.pending) {
            .none => @as(i128, rhs),
            .add => @as(i128, lhs) + @as(i128, rhs),
            .sub => @as(i128, lhs) - @as(i128, rhs),
            .mul => @divTrunc(@as(i128, lhs) * @as(i128, rhs), @as(i128, scale)),
            .div => if (rhs == 0) return null else @divTrunc(@as(i128, lhs) * @as(i128, scale), @as(i128, rhs)),
        };
        return clampI128ToI64(result);
    }

    fn parseDisplay(self: *const App) ?i64 {
        if (self.has_error) return null;
        var sign: i128 = 1;
        var i: usize = 0;
        if (self.display_len > 0 and self.display[0] == '-') {
            sign = -1;
            i = 1;
        }
        var int_part: i128 = 0;
        var frac_part: i128 = 0;
        var frac_digits: usize = 0;
        var seen_dot = false;
        while (i < self.display_len) : (i += 1) {
            const ch = self.display[i];
            if (ch == '.') {
                if (seen_dot) return null;
                seen_dot = true;
                continue;
            }
            if (ch < '0' or ch > '9') return null;
            const digit: i128 = @intCast(ch - '0');
            if (seen_dot) {
                if (frac_digits < 6) {
                    frac_part = frac_part * 10 + digit;
                    frac_digits += 1;
                }
            } else {
                int_part = int_part * 10 + digit;
            }
        }
        while (frac_digits < 6) : (frac_digits += 1) frac_part *= 10;
        return clampI128ToI64(sign * (int_part * @as(i128, scale) + frac_part));
    }

    fn setDisplayScaled(self: *App, value: i64) void {
        var out: [max_display + 1]u8 = .{0} ** (max_display + 1);
        const len = formatScaled(out[0..], value) orelse {
            self.setError();
            return;
        };
        self.display = out;
        self.display_len = len;
        self.has_error = false;
    }

    fn setError(self: *App) void {
        self.pending = .none;
        self.new_input = true;
        self.has_error = true;
        self.setDisplay("Error");
    }

    fn setDisplay(self: *App, value: []const u8) void {
        var len: usize = 0;
        while (len < max_display and len < value.len) : (len += 1) self.display[len] = value[len];
        self.display_len = len;
        if (len <= max_display) self.display[len] = 0;
        var i = len + 1;
        while (i < self.display.len) : (i += 1) self.display[i] = 0;
    }

    fn appendDisplayByte(self: *App, ch: u8) void {
        if (self.display_len >= max_display) return;
        self.display[self.display_len] = ch;
        self.display_len += 1;
        self.display[self.display_len] = 0;
    }

    fn displayText(self: *const App) []const u8 {
        return self.display[0..self.display_len];
    }

    fn displayContains(self: *const App, needle: u8) bool {
        var i: usize = 0;
        while (i < self.display_len) : (i += 1) {
            if (self.display[i] == needle) return true;
        }
        return false;
    }

    fn isZeroDisplay(self: *const App) bool {
        return self.display_len == 1 and self.display[0] == '0';
    }

    fn displayRect(self: *const App) r4os.gui.Rect {
        return .{ .x = 10, .y = 26, .w = self.w - 20, .h = 36 };
    }

    fn buttonRect(self: *const App, row: usize, col: usize) r4os.gui.Rect {
        const pad: i32 = 10;
        const gap: i32 = 6;
        const top: i32 = 74;
        const available_w = @max(64, self.w - pad * 2 - gap * 3);
        const button_w = @divTrunc(available_w, 4);
        const available_h = @max(132, self.h - top - pad - gap * 5);
        const button_h = @divTrunc(available_h, 6);
        return .{
            .x = pad + @as(i32, @intCast(col)) * (button_w + gap),
            .y = top + @as(i32, @intCast(row)) * (button_h + gap),
            .w = button_w,
            .h = button_h,
        };
    }

    fn equalsRect(self: *const App) r4os.gui.Rect {
        const left = self.buttonRect(5, 0);
        const right = self.buttonRect(5, 3);
        return .{ .x = left.x, .y = left.y, .w = right.x + right.w - left.x, .h = left.h };
    }

    fn buttonAt(self: *const App, x: i32, y: i32) ButtonKind {
        if (self.equalsRect().contains(x, y)) return .equals;
        var row: usize = 0;
        while (row < button_grid.len) : (row += 1) {
            var col: usize = 0;
            while (col < button_grid[row].len) : (col += 1) {
                if (self.buttonRect(row, col).contains(x, y)) return button_grid[row][col];
            }
        }
        return .none;
    }
};

fn buttonForKey(key: u8) ButtonKind {
    return switch (key) {
        '0' => .digit0,
        '1' => .digit1,
        '2' => .digit2,
        '3' => .digit3,
        '4' => .digit4,
        '5' => .digit5,
        '6' => .digit6,
        '7' => .digit7,
        '8' => .digit8,
        '9' => .digit9,
        '.', ',' => .decimal,
        '+' => .add,
        '-' => .sub,
        '*', 'x', 'X' => .mul,
        '/' => .div,
        '%' => .percent,
        '=', r4os.gui.Key.enter => .equals,
        r4os.gui.Key.backspace => .backspace,
        r4os.gui.Key.delete => .clear_entry,
        r4os.gui.Key.escape, 'c', 'C' => .clear,
        'e', 'E' => .clear_entry,
        'n', 'N' => .sign,
        else => .none,
    };
}

fn buttonLabel(kind: ButtonKind) []const u8 {
    return switch (kind) {
        .digit0 => "0",
        .digit1 => "1",
        .digit2 => "2",
        .digit3 => "3",
        .digit4 => "4",
        .digit5 => "5",
        .digit6 => "6",
        .digit7 => "7",
        .digit8 => "8",
        .digit9 => "9",
        .decimal => ".",
        .sign => "+/-",
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div => "/",
        .percent => "%",
        .equals => "=",
        .clear => "C",
        .clear_entry => "CE",
        .backspace => "Back",
        .none => "",
    };
}

fn drawSunken(canvas: r4os.gui.Canvas, rect: r4os.gui.Rect) void {
    _ = canvas.rect(rect, palette.face_shadow);
    _ = canvas.rect(.{ .x = rect.x + 1, .y = rect.y + 1, .w = rect.w - 2, .h = rect.h - 2 }, palette.face_light);
    _ = canvas.rect(.{ .x = rect.x + 2, .y = rect.y + 2, .w = rect.w - 4, .h = rect.h - 4 }, display_bg);
}

fn formatScaled(out: []u8, value: i64) ?usize {
    if (out.len == 0) return null;
    var idx: usize = 0;
    var mag: i128 = value;
    if (value < 0) {
        if (idx >= out.len - 1) return null;
        out[idx] = '-';
        idx += 1;
        mag = -mag;
    }

    const int_part: u64 = @intCast(@divTrunc(mag, @as(i128, scale)));
    const frac_part: u64 = @intCast(@mod(mag, @as(i128, scale)));
    idx = appendUnsigned(out, idx, int_part) orelse return null;
    if (frac_part != 0) {
        if (idx >= out.len - 1) return null;
        out[idx] = '.';
        idx += 1;
        var digits: [6]u8 = .{0} ** 6;
        var rem = frac_part;
        var pos: usize = 6;
        while (pos > 0) {
            pos -= 1;
            digits[pos] = @as(u8, @intCast(rem % 10)) + '0';
            rem /= 10;
        }
        var end: usize = 6;
        while (end > 0 and digits[end - 1] == '0') : (end -= 1) {}
        var i: usize = 0;
        while (i < end) : (i += 1) {
            if (idx >= out.len - 1) return null;
            out[idx] = digits[i];
            idx += 1;
        }
    }
    if (idx >= out.len) return null;
    out[idx] = 0;
    return idx;
}

fn appendUnsigned(out: []u8, start: usize, value: u64) ?usize {
    var idx = start;
    if (value == 0) {
        if (idx >= out.len - 1) return null;
        out[idx] = '0';
        return idx + 1;
    }
    var temp: [20]u8 = .{0} ** 20;
    var count: usize = 0;
    var n = value;
    while (n > 0 and count < temp.len) : (count += 1) {
        temp[count] = @as(u8, @intCast(n % 10)) + '0';
        n /= 10;
    }
    while (count > 0) {
        count -= 1;
        if (idx >= out.len - 1) return null;
        out[idx] = temp[count];
        idx += 1;
    }
    return idx;
}

fn clampI128ToI64(value: i128) ?i64 {
    const min: i128 = -9223372036854775808;
    const max: i128 = 9223372036854775807;
    if (value < min or value > max) return null;
    return @intCast(value);
}

fn clampI32(value: i32, min: i32, max: i32) i32 {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}
