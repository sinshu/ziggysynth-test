// Thie FFT implementation was taken from here:
// https://qiita.com/bellbind/items/f2338fa1d82a2a79f290

// A zig program as a library (for FFT implementation)
//NOTE:  This code is written for zig-0.4.0 syntax/builtins/std lib
const pi = @import("std").math.pi;
const sin = @import("std").math.sin;
const cos = @import("std").math.cos;

// complex number type
pub const CN = struct { // "extern struct"  as C struct
    re: f64,
    im: f64,
    pub fn rect(re: f64, im: f64) CN {
        return CN{
            .re = re,
            .im = im,
        };
    }
    pub fn expi(t: f64) CN {
        //NOTE: sin(t) and cos(t) will be @sin(f64, t) and @cos(f64, t) on zig-0.5.0
        return CN{
            .re = cos(t),
            .im = sin(t),
        };
    }
    pub fn add(self: CN, other: CN) CN {
        return CN{
            .re = self.re + other.re,
            .im = self.im + other.im,
        };
    }
    pub fn sub(self: CN, other: CN) CN {
        return CN{
            .re = self.re - other.re,
            .im = self.im - other.im,
        };
    }
    pub fn mul(self: CN, other: CN) CN {
        return CN{
            .re = self.re * other.re - self.im * other.im,
            .im = self.re * other.im + self.im * other.re,
        };
    }
    pub fn rdiv(self: CN, re: f64) CN {
        return CN{
            .re = self.re / re,
            .im = self.im / re,
        };
    }
};
//NOTE: exporting struct returned fn is not allowed for "wasm32" target

test "CN" {
    const assert = @import("std").debug.assert;
    //const warn = @import("std").debug.warn;
    const eps = @import("std").math.f64_epsilon;
    const abs = @import("std").math.fabs;

    const a = CN.rect(1.0, 0.0);
    const b = CN.expi(pi / 2.0);
    assert(a.re == 1.0 and a.im == 0.0);
    //warn("{}+{}i\n", b.re, b.im);
    assert(abs(b.re) < eps and abs(b.im - 1.0) < eps);
    const apb = a.add(b);
    const asb = a.sub(b);
    assert(abs(apb.re - 1.0) < eps and abs(apb.im - 1.0) < eps);
    assert(abs(asb.re - 1.0) < eps and abs(asb.im + 1.0) < eps);
    const bmb = b.mul(b);
    assert(abs(bmb.re + 1.0) < eps and abs(bmb.im) < eps);
    const apb2 = apb.rdiv(2.0);
    assert(abs(apb2.re - 0.5) < eps and abs(apb2.im - 0.5) < eps);
}
test "CN array" {
    const assert = @import("std").debug.assert;
    //const warn = @import("std").debug.warn;
    const eps = @import("std").math.f64_epsilon;
    const abs = @import("std").math.fabs;

    var cns: [2]CN = undefined;
    cns[0] = CN.rect(1.0, 0.0);
    cns[1] = CN.rect(0.0, 1.0);
    cns[0] = cns[0].add(cns[1]);
    assert(abs(cns[0].re - 1.0) < eps and abs(cns[0].im - 1.0) < eps);
}

// reverse as k-bit
fn revbit(k: u32, n0: u32) u32 {
    //NOTE: @bitreverse will be renamed to @bitReverse on zig-0.5.0
    return @bitReverse(n0) >> @truncate(u5, 32 - k);
}

test "revbit" {
    const assert = @import("std").debug.assert;
    const n: u32 = 8;
    const k: u32 = @ctz(n);
    assert(revbit(k, 0) == 0b000);
    assert(revbit(k, 1) == 0b100);
    assert(revbit(k, 2) == 0b010);
    assert(revbit(k, 3) == 0b110);
    assert(revbit(k, 4) == 0b001);
    assert(revbit(k, 5) == 0b101);
    assert(revbit(k, 6) == 0b011);
    assert(revbit(k, 7) == 0b111);
}

// Loop Cooley-Tukey FFT
fn fftc(t0: f64, n: u32, c: [*]CN, r: [*]CN) void {
    {
        const k: u32 = @ctz(n);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            r[i] = c[@call(.always_inline, revbit, .{k, i})];
        }
    }
    var t = t0;
    var nh: u32 = 1;
    while (nh < n) : (nh <<= 1) {
        t /= 2.0;
        const nh2 = nh << 1;
        var s: u32 = 0;
        while (s < n) : (s += nh2) {
            var i: u32 = 0;
            while (i < nh) : (i += 1) {
                const li = s + i;
                const ri = li + nh;
                const re = r[ri].mul(CN.expi(t * @intToFloat(f64, i)));
                const l = r[li];
                r[li] = l.add(re);
                r[ri] = l.sub(re);
            }
        }
    }
}
pub fn fft(n: u32, f: [*]CN, F: [*]CN) void {
    fftc(-2.0 * pi, n, f, F);
}
pub fn ifft(n: u32, F: [*]CN, f: [*]CN) void {
    fftc(2.0 * pi, n, F, f);
    const nf64 = @intToFloat(f64, n);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        f[i] = f[i].rdiv(nf64);
    }
}

test "fft/ifft" {
    const warn = @import("std").debug.warn;
    const assert = @import("std").debug.assert;
    const abs = @import("std").math.fabs;
    const eps = 1e-15;
    //NOTE: On `test` block, `fn` can define in `struct`
    const util = struct {
        fn warnCNs(n: u32, cns: [*]CN) void {
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                warn("{} + {}i\n", cns[i].re, cns[i].im);
            }
        }
    };

    const n: u32 = 16;
    const v = [n]i32{ 1, 3, 4, 2, 5, 6, 2, 4, 0, 1, 3, 4, 5, 62, 2, 3 };
    var f: [n]CN = undefined;
    {
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            f[i] = CN.rect(@intToFloat(f64, v[i]), 0.0);
        }
    }
    warn("\n[f]\n");
    util.warnCNs(n, &f);

    var F: [n]CN = undefined;
    var r: [n]CN = undefined;
    fft(n, &f, &F);
    ifft(n, &F, &r);

    warn("\n[F]\n");
    util.warnCNs(n, &F);
    warn("\n[r]\n");
    util.warnCNs(n, &r);

    {
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            assert(abs(r[i].re - @intToFloat(f64, v[i])) < eps);
        }
    }
}
