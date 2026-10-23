"""Vectorized 2D gradient noise + fBm (numpy) for the world generator. Deterministic per seed."""
import numpy as np


def _hash(ix, iz, seed):
    h = (ix.astype(np.int64) * 374761393 + iz.astype(np.int64) * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return (h ^ (h >> 16)) & 0xFFFFFFFF


def perlin(x, z, seed=0):
    """Gradient noise in [-1, 1] (roughly) at arbitrary float arrays x, z (unit = one cell)."""
    x0 = np.floor(x)
    z0 = np.floor(z)
    fx = x - x0
    fz = z - z0
    ix = x0.astype(np.int64)
    iz = z0.astype(np.int64)

    def grad(i, j, dx, dz):
        a = _hash(i, j, seed).astype(np.float64) / 4294967296.0 * 2.0 * np.pi
        return np.cos(a) * dx + np.sin(a) * dz

    n00 = grad(ix, iz, fx, fz)
    n10 = grad(ix + 1, iz, fx - 1, fz)
    n01 = grad(ix, iz + 1, fx, fz - 1)
    n11 = grad(ix + 1, iz + 1, fx - 1, fz - 1)
    ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
    uz = fz * fz * fz * (fz * (fz * 6 - 15) + 10)
    return (n00 * (1 - ux) + n10 * ux) * (1 - uz) + (n01 * (1 - ux) + n11 * ux) * uz


def fbm(x, z, freq, octaves=4, seed=0, gain=0.5, lacunarity=2.0, ridged=False):
    total = np.zeros_like(x, dtype=np.float64)
    amp = 1.0
    norm = 0.0
    f = freq
    for o in range(octaves):
        n = perlin(x * f, z * f, seed + o * 101)
        if ridged:
            n = 1.0 - np.abs(n) * 1.6
            n = n * n
        total += n * amp
        norm += amp
        amp *= gain
        f *= lacunarity
    return total / norm


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)
