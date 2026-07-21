import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const resourcePath = resolve('Sources/WhatsAppWeb/Resources/WAM/definitions.json')
const resource = JSON.parse(await readFile(resourcePath, 'utf8'))

if (!Array.isArray(resource.events)) {
	throw new Error('WAM definitions resource is missing events')
}

if (!Array.isArray(resource.globals)) {
	throw new Error('WAM definitions resource is missing globals')
}

assertUniqueNames('WAM events', resource.events.map(event => event.name))
assertUniqueNames('WAM globals', resource.globals.map(global => global.name))

const clientErrors = resource.events.find(event => event.name === 'WamClientErrors')
if (clientErrors?.id !== 1144 || clientErrors.weight !== 1 || clientErrors.props?.isFromWamsys !== 27) {
	throw new Error('WamClientErrors definition does not match the expected Baileys contract')
}

const platform = resource.globals.find(global => global.name === 'platform')
if (platform?.id !== 11) {
	throw new Error('platform global definition does not match the expected Baileys contract')
}

function assertUniqueNames(kind, names) {
	const seen = new Set()
	for (const name of names) {
		if (seen.has(name)) {
			throw new Error(`${kind} contains duplicate name: ${name}`)
		}

		seen.add(name)
	}
}
