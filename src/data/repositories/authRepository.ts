import { sleep } from "@/lib/utils"

export type Session = {
  userId: string
  email: string
  name: string
  signedInAt: string
}

export interface AuthRepository {
  /** Future: POST /auth/login against our backend. */
  signIn(input: { email: string; password: string }): Promise<Session>
  signUp(input: { email: string; password: string; name: string }): Promise<Session>
  signOut(): Promise<void>
  restore(): Session | null
}

const SESSION_KEY = "session"

type StorageAdapter = {
  read<T>(key: string): T | null
  write(key: string, value: unknown): void
  remove(key: string): void
}

/**
 * Demo authentication. Any valid email and a password of at least six
 * characters is accepted so the product can be demonstrated without a backend.
 * Swapping in a real repository does not change any screen.
 */
export function createMockAuthRepository(storage: StorageAdapter): AuthRepository {
  return {
    async signIn({ email, password }) {
      await sleep(620)
      if (!email.includes("@")) throw new Error("Enter a valid email address")
      if (password.length < 6) throw new Error("Password must be at least 6 characters")
      const session: Session = {
        userId: "u_1",
        email,
        name: email.split("@")[0].replace(/[._]/g, " "),
        signedInAt: new Date().toISOString(),
      }
      storage.write(SESSION_KEY, session)
      return session
    },

    async signUp({ email, password, name }) {
      await sleep(680)
      if (!email.includes("@")) throw new Error("Enter a valid email address")
      if (password.length < 6) throw new Error("Password must be at least 6 characters")
      const session: Session = {
        userId: "u_1",
        email,
        name: name || email.split("@")[0],
        signedInAt: new Date().toISOString(),
      }
      storage.write(SESSION_KEY, session)
      return session
    },

    async signOut() {
      await sleep(180)
      storage.remove(SESSION_KEY)
    },

    restore() {
      const session = storage.read<Session>(SESSION_KEY)
      if (!session || typeof session.email !== "string") return null
      return session
    },
  }
}
