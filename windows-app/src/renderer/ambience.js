// The study sounds: four lo-fi stations and three nature beds. Ported from Ambience in Focus.swift.
export const STATIONS = ['lofi', 'rainy', 'cafe', 'night']
export const NATURE = ['rain', 'brown', 'waves']

export const Ambience = {
  off: { id: 'off', title: 'Off', short: 'Off', emoji: '🔇', mood: '' },
  lofi: { id: 'lofi', title: 'Lo-fi Chill', short: 'Chill', emoji: '🎧', mood: 'soft piano, mellow drums' },
  rainy: { id: 'rainy', title: 'Rainy Beats', short: 'Rainy', emoji: '🌧️', mood: 'rain on the window' },
  cafe: { id: 'cafe', title: 'Café Jazz', short: 'Café', emoji: '☕️', mood: 'swingy coffee-shop jazz' },
  night: { id: 'night', title: 'Night Study', short: 'Night', emoji: '🌙', mood: 'slow & glowy, for late shifts' },
  rain: { id: 'rain', title: 'Rain', short: 'Rain', emoji: '💧', mood: 'just rain' },
  brown: { id: 'brown', title: 'Brown noise', short: 'Brown', emoji: '🌫️', mood: 'deep, steady hush' },
  waves: { id: 'waves', title: 'Waves', short: 'Waves', emoji: '🌊', mood: 'slow ocean swell' },
}
export const isMusic = (k) => STATIONS.includes(k)
