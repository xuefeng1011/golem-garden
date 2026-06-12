/**
 * Fire a Web Notification only when the tab is hidden (backgrounded).
 *
 * Used to announce run completion when the user has switched away from the
 * tab. Permission is requested lazily on the first send attempt; if the user
 * denied (or the browser lacks the API), this silently no-ops. Zero deps.
 */
export async function notifyWhenHidden(title: string, body: string): Promise<boolean> {
  if (typeof document === 'undefined' || !document.hidden) return false
  if (typeof Notification === 'undefined') return false

  let permission = Notification.permission
  if (permission === 'default') {
    try {
      permission = await Notification.requestPermission()
    } catch {
      return false
    }
  }
  if (permission !== 'granted') return false

  try {
    new Notification(title, body ? { body } : undefined)
    return true
  } catch {
    return false
  }
}
