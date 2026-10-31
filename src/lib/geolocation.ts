// Browser-only helpers around navigator.geolocation.
export function getPosition(): Promise<GeolocationPosition> {
  return new Promise((resolve, reject) => {
    if (!("geolocation" in navigator)) return reject(new Error("unsupported"));
    navigator.geolocation.getCurrentPosition(resolve, reject, { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 });
  });
}

export function locationErrorMessage(e: unknown) {
  const code = (e as GeolocationPositionError)?.code;
  if (code === 1) return "Location is blocked. Allow it for this site in your browser settings, then try again.";
  if (code === 3) return "Finding your location took too long. Try again, ideally near a window.";
  if (e instanceof Error && e.message === "unsupported") return "This browser can't share its location. Try your phone.";
  return "Couldn't get your location. Try again.";
}
