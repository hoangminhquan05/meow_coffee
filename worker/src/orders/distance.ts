// Quãng đường quán → địa chỉ: OSRM (đường đi thực tế), lỗi thì chim bay × 1.3 (O8).

export const ROAD_FACTOR = 1.3;

export function haversineKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

export async function roadDistanceKm(
  from: { lat: number; lng: number },
  to: { lat: number; lng: number },
): Promise<{ km: number; source: 'osrm' | 'haversine' }> {
  try {
    const url =
      `https://router.project-osrm.org/route/v1/driving/` +
      `${from.lng},${from.lat};${to.lng},${to.lat}?overview=false`;
    const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
    const body = (await res.json()) as { code?: string; routes?: { distance: number }[] };
    if (!res.ok || body.code !== 'Ok' || !body.routes?.length) throw new Error(body.code);
    return { km: body.routes[0].distance / 1000, source: 'osrm' };
  } catch {
    return { km: haversineKm(from, to) * ROAD_FACTOR, source: 'haversine' };
  }
}
