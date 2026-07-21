import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const resourcePath = resolve('Sources/WhatsAppWeb/Resources/Binary/tokens.json')
const resource = JSON.parse(await readFile(resourcePath, 'utf8'))

if (!Array.isArray(resource.singleByteTokens)) {
	throw new Error('Binary token resource is missing singleByteTokens')
}

if (!Array.isArray(resource.doubleByteTokens)) {
	throw new Error('Binary token resource is missing doubleByteTokens')
}

if (resource.singleByteTokens.length !== 236) {
	throw new Error(`Expected 236 single-byte tokens, found ${resource.singleByteTokens.length}`)
}

if (resource.doubleByteTokens.length !== 4) {
	throw new Error(`Expected 4 double-byte token dictionaries, found ${resource.doubleByteTokens.length}`)
}

if (!resource.singleByteTokens.includes('message')) {
	throw new Error('Single-byte token table is missing the message token')
}

if (resource.doubleByteTokens[0]?.[68] !== 'tokens') {
	throw new Error('Double-byte token table is missing the expected tokens sentinel')
}
