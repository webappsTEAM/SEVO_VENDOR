import React, { useRef, useEffect, useCallback } from 'react';

/**
 * Round 8 gap 2: minimal canvas-based signature capture.
 *
 * No dedicated signature-pad library is a dependency of this frontend today,
 * so rather than pull one in for an optional field, this is a small
 * mouse/touch-draw-to-dataURL canvas -- the same trade-off the task called
 * for. Output is a base64 PNG data URL (onChange), which the vendor
 * backend's WorkforceJobProofView accepts as `signature_data_url`.
 */
export default function SignaturePad({ onChange, height = 120 }) {
  const canvasRef = useRef(null);
  const drawing = useRef(false);
  const empty = useRef(true);

  const getPos = useCallback((e) => {
    const canvas = canvasRef.current;
    const rect = canvas.getBoundingClientRect();
    const point = e.touches && e.touches.length ? e.touches[0] : e;
    return {
      x: (point.clientX - rect.left) * (canvas.width / rect.width),
      y: (point.clientY - rect.top) * (canvas.height / rect.height),
    };
  }, []);

  const start = useCallback((e) => {
    e.preventDefault();
    drawing.current = true;
    const ctx = canvasRef.current.getContext('2d');
    const { x, y } = getPos(e);
    ctx.beginPath();
    ctx.moveTo(x, y);
  }, [getPos]);

  const move = useCallback((e) => {
    if (!drawing.current) return;
    e.preventDefault();
    const ctx = canvasRef.current.getContext('2d');
    const { x, y } = getPos(e);
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.strokeStyle = '#1e293b';
    ctx.lineTo(x, y);
    ctx.stroke();
    empty.current = false;
  }, [getPos]);

  const end = useCallback(() => {
    if (!drawing.current) return;
    drawing.current = false;
    if (onChange && !empty.current) {
      onChange(canvasRef.current.toDataURL('image/png'));
    }
  }, [onChange]);

  const clear = useCallback(() => {
    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    empty.current = true;
    if (onChange) onChange(null);
  }, [onChange]);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
  }, []);

  return (
    <div>
      <canvas
        ref={canvasRef}
        width={320}
        height={height}
        className="w-full border border-slate-300 rounded-lg bg-white touch-none cursor-crosshair"
        onMouseDown={start}
        onMouseMove={move}
        onMouseUp={end}
        onMouseLeave={end}
        onTouchStart={start}
        onTouchMove={move}
        onTouchEnd={end}
      />
      <button
        type="button"
        onClick={clear}
        className="mt-1 text-[11px] font-semibold text-slate-500 hover:text-slate-700 cursor-pointer"
      >
        Clear signature
      </button>
    </div>
  );
}
