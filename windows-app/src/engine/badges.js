// Little collectables for real milestones, worked out from her saved history so they can never
// get out of step with the numbers, plus the tiny daily habits. Ported from Badges.swift.
const B = (id, emoji, title, detail, target, value, unit = '') => ({ id, emoji, title, detail, target, value, unit })

export const BADGES = [
  B('first', '🌱', 'First steps', 'Focus for your first few minutes', 3, (p) => p.totalFocusMinutes, 'min'),
  B('sess1', '🍵', 'First sip', 'Finish your first focus session', 1, (p) => p.totalSessions, 'session'),
  B('mood1', '💌', 'Checked in', 'Tell her how you feel', 1, (p) => Object.keys(p.moods).length, 'check-in'),
  B('habit1', '🌷', 'Little habits', 'Tick off every daily habit in one day', 1, (p) => p.prefs.get('perfectHabitDays'), 'day'),
  B('streak3', '🔥', 'On a roll', 'A 3 day streak', 3, (p) => p.bestStreakDays, 'days'),
  B('streak7', '💪', 'Week warrior', 'A 7 day streak', 7, (p) => p.bestStreakDays, 'days'),
  B('streak14', '⚡️', 'Unstoppable', 'A 14 day streak', 14, (p) => p.bestStreakDays, 'days'),
  B('streak30', '👑', 'Legend', 'A 30 day streak', 30, (p) => p.bestStreakDays, 'days'),
  B('streak100', '🏰', 'Forever bestie', 'A 100 day streak', 100, (p) => p.bestStreakDays, 'days'),
  B('hour', '⏱', 'Focus hour', 'An hour of focus in one day', 60, (p) => p.mostFocusInADay, 'min'),
  B('deep', '🧠', 'Deep work', '3 hours of focus in one day', 180, (p) => p.mostFocusInADay, 'min'),
  B('marathon', '🏔', 'Study marathon', '5 hours of focus in one day', 300, (p) => p.mostFocusInADay, 'min'),
  B('total10', '📚', '10 hours in', '10 hours of focus, all time', 600, (p) => p.totalFocusMinutes, 'min'),
  B('total50', '🎓', '50 hour scholar', '50 hours of focus, all time', 3000, (p) => p.totalFocusMinutes, 'min'),
  B('total100', '🌟', '100 hour club', '100 hours of focus, all time', 6000, (p) => p.totalFocusMinutes, 'min'),
  B('goal1', '🎯', 'Goal getter', 'Hit your daily goal', 1, (p) => p.daysAtGoal, 'day'),
  B('goal7', '🏆', 'Goal machine', 'Hit your goal on 7 days', 7, (p) => p.daysAtGoal, 'days'),
  B('goal30', '💎', 'Diamond habits', 'Hit your goal on 30 days', 30, (p) => p.daysAtGoal, 'days'),
  B('sess5', '🍅', 'Pomodoro pro', 'Finish 5 focus sessions', 5, (p) => p.totalSessions, 'sessions'),
  B('sess25', '🌟', 'Session star', 'Finish 25 focus sessions', 25, (p) => p.totalSessions, 'sessions'),
  B('sess100', '🪐', 'Orbit master', 'Finish 100 focus sessions', 100, (p) => p.totalSessions, 'sessions'),
  B('angel', '😇', 'Angel day', 'An hour of focus without a single bark', 1, (p) => p.angelDays, 'day'),
  B('tasks10', '✅', 'Task tamer', 'Finish 10 to-dos', 10, (p) => p.totalTasksDone, 'to-dos'),
  B('tasks50', '👸', 'Productivity queen', 'Finish 50 to-dos', 50, (p) => p.totalTasksDone, 'to-dos'),
  B('tasks200', '🦄', 'Unicorn energy', 'Finish 200 to-dos', 200, (p) => p.totalTasksDone, 'to-dos'),
  B('early', '🌅', 'Early bird', 'Focus before 8am', 1, (p) => (p.prefs.get('earlyBird') ? 1 : 0)),
  B('owl', '🦉', 'Night owl', 'Focus after 11pm', 1, (p) => (p.prefs.get('nightOwl') ? 1 : 0)),
  B('selfaware', '🪞', 'Self-aware', 'Check in on your mood on 7 days', 7, (p) => Object.keys(p.moods).length, 'days'),
  B('lofi', '🎧', 'Lo-fi girl', 'Study to an hour of music', 60, (p) => p.prefs.get('musicMinutes'), 'min'),
  B('snack', '🍓', 'Snack time', 'Feed her 10 treats', 10, (p) => p.treatsEaten, 'treats'),
  B('dressed', '🎀', 'Dress-up queen', 'Wear something in all three spots', 1,
    (p) => (p.outfit.head !== 'none' && p.outfit.face !== 'none' && p.outfit.neck !== 'none' ? 1 : 0)),
  B('decor', '🛋', 'Cosy corner', 'Put 3 things in her room', 3, (p) => p.decorOn.size, 'things'),
  B('lvl5', '🌿', 'Growing up', 'Reach level 5', 5, (p) => p.level, 'levels'),
  B('lvl10', '✨', 'Besties', 'Reach level 10', 10, (p) => p.level, 'levels'),
  B('lvl20', '💫', 'Soulmates', 'Reach level 20', 20, (p) => p.level, 'levels'),
]

export const badgeEarned = (b, pet) => b.value(pet) >= b.target
export const badgeProgress = (b, pet) => Math.min(1, Math.max(0, b.value(pet) / Math.max(1, b.target)))
export const badgeProgressText = (b, pet) => `${Math.floor(Math.min(b.value(pet), b.target))} of ${b.target}${b.unit ? ' ' + b.unit : ''}`

export function nextUp(pet) {
  const earned = pet.prefs.badgeSet
  const open = BADGES.filter((b) => !earned.has(b.id))
  return open.reduce((best, b) => (!best || badgeProgress(b, pet) > badgeProgress(best, pet) ? b : best), null)
}

export const HABITS = [
  { id: 'water', emoji: '💧', title: 'Drink some water' },
  { id: 'stretch', emoji: '🧘', title: 'Stretch for a minute' },
  { id: 'eyes', emoji: '👀', title: 'Rest your eyes (20-20-20)' },
  { id: 'focus', emoji: '📚', title: 'Focus for 25 minutes', auto: (p) => p.focusTodayMinutes >= 25 },
  { id: 'tidy', emoji: '🌸', title: 'Tidy your desk' },
]
export const HABIT_XP = 4, HABIT_BERRIES = 3, HABIT_BONUS = 10
