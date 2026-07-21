import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'

const inputPath = resolve('Proto/WAProto.proto')
const outputPath = resolve('.generated/WAProto.proto')
const source = await readFile(inputPath, 'utf8')
const lines = source.split('\n')
const output = []

for (let index = 0; index < lines.length; index++) {
	const line = lines[index]
	const enumMatch = line.match(/^(\s*)enum\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{/)

	if (!enumMatch) {
		output.push(line)
		continue
	}

	const enumLines = [line]
	let cursor = index + 1
	for (; cursor < lines.length; cursor++) {
		enumLines.push(lines[cursor])
		if (/^\s*}/.test(lines[cursor])) {
			break
		}
	}

	const firstValue = enumLines.find(enumLine => /^\s*[A-Za-z_][A-Za-z0-9_]*\s*=/.test(enumLine))
	const firstValueNumber = firstValue?.match(/=\s*(-?\d+)/)?.[1]
	output.push(enumLines[0])

	if (firstValueNumber !== '0') {
		const indent = `${enumMatch[1]}    `
		const unknownName = `${enumMatch[2].replaceAll(/[^A-Za-z0-9_]/g, '_').toUpperCase()}_UNKNOWN`
		output.push(`${indent}${unknownName} = 0;`)
	}

	output.push(...enumLines.slice(1))
	index = cursor
}

await mkdir(dirname(outputPath), { recursive: true })
await writeFile(outputPath, output.join('\n'))
