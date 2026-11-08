const store = new Map<string, any>();
const p = { getSync: (k: string, d: any) => (store.has(k) ? store.get(k) : d), putSync: (k: string, v: any) => { store.set(k, v); }, flush: async () => {} };
export const preferences = { getPreferencesSync: () => p, removePreferencesFromCacheSync: () => {} };
export type preferences = any;
