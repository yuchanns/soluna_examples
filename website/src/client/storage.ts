interface RuntimeModuleWithStorage {
  FS: {
    mkdir: (path: string) => void
    mount: (type: unknown, options: Record<string, unknown>, mountpoint: string) => void
    syncfs: (populate: boolean, callback: (error: unknown) => void) => void
  }
  IDBFS?: unknown
}

export function initPersistentStorage(runtimeModule: RuntimeModuleWithStorage): void {
  if (!runtimeModule.IDBFS) {
    return
  }

  try {
    runtimeModule.FS.mkdir('/persistent')
  }
  catch (error) {
    if (!String(error).includes('File exists')) {
      console.warn('Failed to create /persistent', error)
    }
  }

  try {
    runtimeModule.FS.mount(runtimeModule.IDBFS, { autoPersist: true }, '/persistent')
    runtimeModule.FS.syncfs(true, (error) => {
      if (error) {
        console.error('Failed to sync from IDBFS', error)
      }
    })
  }
  catch (error) {
    console.warn('Failed to init persistent storage', error)
  }
}
