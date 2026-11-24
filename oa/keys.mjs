// Derive the key material Open Analytics expects as files from one seed per purpose (OA_QUERY_SEED, OA_REALTIME_SEED, OA_KEYRING_SEED).
// Upstream generates two Ed25519 pairs and a 32-byte credential keyring in a one-shot container and shares them by volume.
// Railway services cannot share a volume, so every role derives the halves it is allowed to hold, deterministically.
// usage: node keys.mjs <outdir> <part>...   parts: query-private query-public realtime-private realtime-public keyring
import { createHmac, createPrivateKey, createPublicKey } from 'node:crypto'
import { mkdirSync, rmSync, writeFileSync } from 'node:fs'

const [outdir, ...parts] = process.argv.slice(2)
const SEEDS = { query: 'OA_QUERY_SEED', realtime: 'OA_REALTIME_SEED', keyring: 'OA_KEYRING_SEED' }
const seedFor = (purpose) => {
  const seed = process.env[SEEDS[purpose]] ?? ''
  if (seed.length < 32) {
    console.error('oa-keys: ' + SEEDS[purpose] + ' must be at least 32 characters')
    process.exit(1)
  }
  return seed
}
const derive = (purpose, label) => createHmac('sha256', seedFor(purpose)).update(`openanalytics-railway/${label}`).digest()
// PKCS#8 prefix of an Ed25519 private key, followed by the 32-byte seed.
const PKCS8 = Buffer.from('302e020100300506032b657004220420', 'hex')
const priv = (purpose) => createPrivateKey({ key: Buffer.concat([PKCS8, derive(purpose, purpose)]), format: 'der', type: 'pkcs8' })
mkdirSync(outdir, { recursive: true, mode: 0o700 })
const write = (name, data) => { rmSync(`${outdir}/${name}`, { force: true }); writeFileSync(`${outdir}/${name}`, data, { mode: 0o400 }) }
for (const part of parts) {
  switch (part) {
    case 'query-private':
      write('query.private.pem', priv('query').export({ type: 'pkcs8', format: 'pem' }))
      break
    case 'query-public':
      write('query.public.pem', createPublicKey(priv('query')).export({ type: 'spki', format: 'pem' }))
      break
    case 'realtime-private':
      write('realtime.private.pem', priv('realtime').export({ type: 'pkcs8', format: 'pem' }))
      break
    case 'realtime-public':
      write('realtime.public.pem', createPublicKey(priv('realtime')).export({ type: 'spki', format: 'pem' }))
      break
    case 'keyring':
      write('credential-keyring.json', JSON.stringify({ active: 'k1', keys: { k1: derive('keyring', 'credential-keyring').toString('base64') } }))
      break
    default:
      console.error(`oa-keys: unknown part ${part}`)
      process.exit(1)
  }
}
