--!strict
--[[
	CrateSequence : déroulé de l'ouverture d'une caisse du Holo-Bazar (module PUR).

	Toute la scène (CrateScene, côté client) est une fonction du temps écoulé :
	« Passer » revient à se placer à la fin. Ce module donne la phase en cours
	et sa progression, et la liste des « pixels » qui assemblent la caisse.
]]

local CrateSequence = {}

export type Phase = { name: string, duration: number }
export type Step = { name: string, start: number, finish: number }
export type Timeline = { steps: { Step }, total: number }

function CrateSequence.timeline(phases: { Phase }): Timeline
	local steps: { Step } = {}
	local clock = 0
	for _, phase in phases do
		table.insert(steps, { name = phase.name, start = clock, finish = clock + phase.duration })
		clock += phase.duration
	end
	return { steps = steps, total = clock }
end

-- Début et fin d'une phase (nil si elle n'existe pas).
function CrateSequence.step(timeline: Timeline, name: string): Step?
	for _, step in timeline.steps do
		if step.name == name then
			return step
		end
	end
	return nil
end

-- Progression d'une phase à l'instant `t` : 0 avant, 1 après.
function CrateSequence.progress(timeline: Timeline, name: string, t: number): number
	local step = CrateSequence.step(timeline, name)
	if step == nil then
		return 0
	end
	if step.finish <= step.start then
		return if t >= step.start then 1 else 0
	end
	return math.clamp((t - step.start) / (step.finish - step.start), 0, 1)
end

-- Phase en cours à l'instant `t` ("done" une fois la séquence terminée).
function CrateSequence.phaseAt(timeline: Timeline, t: number): string
	for _, step in timeline.steps do
		if t < step.finish then
			return step.name
		end
	end
	return "done"
end

export type Voxel = { position: Vector3, size: Vector3 }

--[[
	Pixels de la caisse : la boîte `size` (centrée sur l'origine) découpée en
	cases d'environ `cell` studs. Seule l'enveloppe est gardée (l'intérieur ne
	se voit pas). Ordre d'apparition : du bas vers le haut, et dans une même
	couche dans un ordre mélangé mais toujours le même (aucun hasard).
]]
function CrateSequence.voxels(size: Vector3, cell: number): { Voxel }
	local nx = math.max(1, math.floor(size.X / cell + 0.5))
	local ny = math.max(1, math.floor(size.Y / cell + 0.5))
	local nz = math.max(1, math.floor(size.Z / cell + 0.5))
	local step = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
	local list: { { voxel: Voxel, y: number, key: number } } = {}
	for iy = 1, ny do
		for ix = 1, nx do
			for iz = 1, nz do
				local shell = ix == 1 or ix == nx or iy == 1 or iy == ny or iz == 1 or iz == nz
				if shell then
					local position = Vector3.new(
						-size.X / 2 + (ix - 0.5) * step.X,
						-size.Y / 2 + (iy - 0.5) * step.Y,
						-size.Z / 2 + (iz - 0.5) * step.Z
					)
					-- Mélange stable dans la couche (hachage entier des indices).
					local key = (ix * 73856093 + iz * 19349663) % 1000
					table.insert(list, { voxel = { position = position, size = step }, y = iy, key = key })
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.y ~= b.y then
			return a.y < b.y
		end
		if a.key ~= b.key then
			return a.key < b.key
		end
		return a.voxel.position.X + a.voxel.position.Z * 0.001 < b.voxel.position.X + b.voxel.position.Z * 0.001
	end)
	local voxels: { Voxel } = {}
	for index, entry in list do
		voxels[index] = entry.voxel
	end
	return voxels
end

-- Nombre de pixels apparus à la progression `p` (0 à 1) d'une phase de construction.
function CrateSequence.spawned(count: number, p: number): number
	return math.clamp(math.floor(p * count + 1e-9), 0, count)
end

return CrateSequence
