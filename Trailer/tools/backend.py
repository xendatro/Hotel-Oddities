import math

import cv2
import numpy as np

try:
    import warnings

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        import cupy
        from cupyx.scipy import ndimage as cupy_ndimage
    HAS_GPU = cupy.cuda.runtime.getDeviceCount() > 0
except Exception:
    cupy = None
    cupy_ndimage = None
    HAS_GPU = False


class Backend:
    def __init__(self, gpu=True):
        self.gpu = bool(gpu and HAS_GPU)
        self.xp = cupy if self.gpu else np

    @property
    def name(self):
        return "gpu" if self.gpu else "cpu"

    def array(self, value, dtype=np.float32):
        return self.xp.asarray(value, dtype=dtype)

    def host(self, value):
        return cupy.asnumpy(value) if self.gpu else value

    def shrink4(self, x):
        if self.gpu:
            height, width = x.shape[:2]
            return x[: height // 4 * 4, : width // 4 * 4].reshape(height // 4, 4, width // 4, 4, -1).mean(axis=(1, 3))
        return cv2.resize(x, (x.shape[1] // 4, x.shape[0] // 4), interpolation=cv2.INTER_AREA)

    def grow(self, x, width, height):
        if self.gpu:
            factors = (height / x.shape[0], width / x.shape[1]) + ((1,) if x.ndim == 3 else ())
            out = cupy_ndimage.zoom(x, factors, order=1, mode="nearest", grid_mode=True)
            return out[:height, :width]
        return cv2.resize(x, (width, height), interpolation=cv2.INTER_LINEAR)

    def blur(self, x, sigma):
        if self.gpu:
            sigmas = (sigma, sigma) + ((0,) if x.ndim == 3 else ())
            return cupy_ndimage.gaussian_filter(x, sigmas, mode="reflect", truncate=3.0)
        return cv2.GaussianBlur(x, (0, 0), sigma)

    def scale_channel(self, channel, scale):
        height, width = channel.shape
        cx, cy = (width - 1) / 2, (height - 1) / 2
        if self.gpu:
            matrix = cupy.asarray([[1 / scale, 0], [0, 1 / scale]], dtype=cupy.float32)
            offset = (cy - cy / scale, cx - cx / scale)
            return cupy_ndimage.affine_transform(channel, matrix, offset=offset, order=1, mode="reflect")
        matrix = np.float32([[scale, 0, cx - cx * scale], [0, scale, cy - cy * scale]])
        return cv2.warpAffine(np.ascontiguousarray(channel), matrix, (width, height), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)

    def transform(self, x, dx, dy, angle, zoom):
        height, width = x.shape[:2]
        cx, cy = (width - 1) / 2, (height - 1) / 2
        if self.gpu:
            radians = math.radians(angle)
            cos, sin = math.cos(radians) / zoom, math.sin(radians) / zoom
            inverse = cupy.asarray([[cos, sin, 0], [-sin, cos, 0], [0, 0, 1]], dtype=cupy.float32)
            center = np.array([cy, cx, 0])
            shift = np.array([dy, dx, 0])
            offset = center - inverse.get() @ (center + shift)
            return cupy_ndimage.affine_transform(x, inverse, offset=offset, order=1, mode="reflect")
        matrix = cv2.getRotationMatrix2D((cx, cy), angle, zoom)
        matrix[0, 2] += dx
        matrix[1, 2] += dy
        return cv2.warpAffine(x, matrix, (width, height), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
