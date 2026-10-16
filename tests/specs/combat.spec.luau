--!nocheck
-- Logique de combat : dégâts, parade, armes, postures, validation des tirs.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local roblox = require("@lune/roblox")
	local Vector3 = roblox.Vector3
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local Damage = H.require("ReplicatedStorage/Shared/Combat/Damage")
	local WeaponLogic = H.require("ReplicatedStorage/Shared/Combat/WeaponLogic")
	local Movement = H.require("ReplicatedStorage/Shared/Combat/Movement")
	local Projectiles = H.require("ReplicatedStorage/Shared/Combat/Projectiles")
	local HitValidator = H.require("ServerScriptService/Server/Combat/HitValidator")
	local Fighter = H.require("ServerScriptService/Server/Combat/Fighter")

	local W = Config.Weapons.ranged
	local helmet = function(condition)
		return { uid = "h", itemId = "helmet", condition = condition }
	end

	describe("Damage", function()
		it("dégressivité au-delà de la portée efficace", function()
			expect(Damage.falloff(100, 50)).toBe(1)
			expect(Damage.falloff(100, 100)).toBe(1)
			expect(Damage.falloff(100, 150)).toBeNear(0.75)
			expect(Damage.falloff(100, 200)).toBeNear(0.5)
			expect(Damage.falloff(100, 299)).toBeNear(0.5)
			expect(Damage.falloff(100, 301)).toBe(0)
		end)

		it("dégâts d'arme × état, tête × casque", function()
			local base = { def = W.sentinel_rifle, condition = 4, distance = 10, isHead = false, targetKind = "player" }
			expect(Damage.ranged(base)).toBeNear(17)
			base.condition = 5
			expect(Damage.ranged(base)).toBeNear(17 * 1.15)
			base.condition = 1
			expect(Damage.ranged(base)).toBeNear(17 * 0.7)
			base.condition = 4
			base.isHead = true
			expect(Damage.ranged(base)).toBeNear(34) -- sans casque ×2
			base.helmet = helmet(5)
			expect(Damage.ranged(base)).toBeNear(17 * 1.3)
		end)

		it("pas de multiplicateur de tête pour le rayon et les explosions", function()
			local hit = { def = W.xray_cannon, condition = 4, distance = 5, isHead = true, targetKind = "player" }
			-- Rayon continu : 60 dégâts par seconde, appliqués par tics.
			expect(Damage.ranged(hit)).toBeNear(60 * W.xray_cannon.beamTick)
			hit.def = W.short_circuit
			expect(Damage.ranged(hit)).toBeNear(70)
			hit.targetKind = "robot"
			hit.isHead = false
			expect(Damage.ranged(hit)).toBeNear(175) -- ×2,5 contre les robots
		end)

		it("le bouclier absorbe avant les PV", function()
			local r = Damage.apply(100, 70, 50)
			expect(r.shield).toBe(20)
			expect(r.health).toBe(100)
			r = Damage.apply(100, 20, 50)
			expect(r.shield).toBe(0)
			expect(r.health).toBe(70)
			r = Damage.apply(10, 0, 50)
			expect(r.health).toBe(0)
			expect(r.healthDamage).toBe(10)
		end)

		it("lame vibrante : ignore 50 % du bouclier", function()
			local r = Damage.apply(100, 100, 45, 0.5)
			expect(r.shield).toBeNear(100 - 22.5)
			expect(r.health).toBeNear(100 - 22.5)
		end)

		it("ordre de grandeur du temps pour tuer (0,6 à 1,2 s visé)", function()
			-- Fusil de Sentinelle (Bon état) contre 100 PV + gilet Bon état (70).
			local rifle = W.sentinel_rifle
			local shots = math.ceil(170 / rifle.damage)
			local ttk = (shots - 1) / rifle.fireRate
			expect(ttk > 0.6 and ttk < 1.6).toBe(true)
		end)
	end)

	describe("Armes spéciales", function()
		it("Canon à rayons X : 60 dégâts/s, moitié à travers un couvert léger", function()
			local def = W.xray_cannon
			local hit = { def = def, condition = 4, distance = 10, isHead = false, targetKind = "player" }
			local perSecond = Damage.ranged(hit) / WeaponLogic.fireInterval(def)
			expect(perSecond).toBeNear(60)
			hit.throughCover = true
			expect(Damage.ranged(hit) / WeaponLogic.fireInterval(def)).toBeNear(30)
			-- Une arme qui ne traverse pas les couverts ne fait aucun dégât à travers.
			expect(Damage.ranged({
				def = W.sentinel_rifle,
				condition = 4,
				distance = 10,
				isHead = false,
				targetKind = "player",
				throughCover = true,
			})).toBe(0)
		end)

		it("Canon à rayons X : +25 de chaleur/s, 1 cellule / 0,5 s, surchauffe en 4 s", function()
			local def = W.xray_cannon
			local s = WeaponLogic.new(def)
			expect(WeaponLogic.fireInterval(def)).toBeNear(0.1)
			local time, cells, ticks = 0, 0, 0
			-- Une seconde de rayon.
			for _ = 1, 10 do
				expect(WeaponLogic.canFire(def, s, time, 100)).toBe(true)
				cells += WeaponLogic.fire(def, s, time).cellsConsumed
				time += def.beamTick
				ticks += 1
			end
			expect(s.heat).toBeNear(25)
			expect(cells).toBe(2)
			-- Trop tôt entre deux tics : refusé (plus de tir « gratuit » sans cadence).
			local ok, why = WeaponLogic.canFire(def, s, time - def.beamTick + 0.01, 100)
			expect(ok).toBe(false)
			expect(why).toBe("cooldown")
			while true do
				local result = WeaponLogic.fire(def, s, time)
				time += def.beamTick
				ticks += 1
				if result.overheated then
					break
				end
			end
			expect(ticks).toBe(40) -- 4 secondes
			-- Sans cellule : pas de rayon.
			local empty = WeaponLogic.new(def)
			local allowed, block = WeaponLogic.canFire(def, empty, 0, 0)
			expect(allowed).toBe(false)
			expect(block).toBe("no_cells")
		end)

		it("Sabre laser : renvoi seulement en état Neuf, de face, dans la fenêtre de parade parfaite", function()
			local base =
				{ parrying = true, parryStartedAt = 10, now = 10.2, frontal = true, reflects = true, condition = 5 }
			expect(Damage.reflectsShot(base)).toBe(true)
			for key, value in { condition = 4, frontal = false, parrying = false, reflects = false, now = 10.3 } do
				local changed = table.clone(base)
				changed[key] = value
				expect(Damage.reflectsShot(changed)).toBe(false)
			end
		end)

		-- Monde de test : un sol à y = 0 et, en option, un mur vertical à z = wallZ.
		local function world(wallZ)
			return function(_projectile, from, displacement)
				local best
				if displacement.Y < 0 and from.Y > 0 then
					local t = from.Y / -displacement.Y
					if t <= 1 then
						best = t
					end
				end
				if wallZ and displacement.Z < 0 and from.Z > wallZ then
					local t = (from.Z - wallZ) / -displacement.Z
					if t <= 1 and (best == nil or t < best) then
						best = t
					end
				end
				if best then
					return from + displacement * best, "obstacle"
				end
				return nil, nil
			end
		end

		local function fly(projectile, cast)
			local list = { projectile }
			local impacts = {}
			local time = 0
			while #list > 0 and time < 20 do
				time += 1 / 60
				Projectiles.step(list, 1 / 60, time, cast, function(_p, position, instance)
					table.insert(impacts, { position = position, instance = instance, time = time })
				end)
			end
			return impacts
		end

		it("Lance-clous : projectile droit à 250 studs/s, arrêté par le premier obstacle", function()
			local def = W.mag_nailer
			local origin = Vector3.new(0, 5, 0)
			local p = Projectiles.new(origin, Vector3.new(0, 0, -def.projectileSpeed), 0, 300, 6, nil)
			local impacts = fly(p, world(-100))
			expect(#impacts).toBe(1)
			expect(impacts[1].position.Z).toBeNear(-100, 0.01)
			expect(impacts[1].instance).toBe("obstacle")
			expect(impacts[1].time).toBeNear(100 / 250, 0.03)
			-- Sans obstacle : il s'éteint au bout de sa portée, sans rien toucher.
			local lost = fly(Projectiles.new(origin, Vector3.new(0, 0, -250), 0, 300, 6, nil), function()
				return nil, nil
			end)
			expect(#lost).toBe(1)
			expect(lost[1].instance).toBeNil()
			expect((lost[1].position - origin).Magnitude >= 300).toBe(true)
		end)

		it("Court-Circuit : tir en cloche qui retombe sur le point visé", function()
			local def = W.short_circuit
			local origin = Vector3.new(0, 5, 0)
			for _, target in { Vector3.new(0, 0, -40), Vector3.new(30, 0, -60), Vector3.new(-10, 0, -100) } do
				local direction = Projectiles.ballisticDirection(origin, target, def.projectileSpeed, def.arcGravity)
				expect(direction.Magnitude).toBeNear(1)
				local p = Projectiles.new(origin, direction * def.projectileSpeed, def.arcGravity, 210, 6, nil)
				local impacts = fly(p, world(nil))
				expect(#impacts).toBe(1)
				expect((impacts[1].position - target).Magnitude < 1.5).toBe(true)
			end
			-- Hors de portée (v² / g = 135 studs) : tir à 45°.
			local far =
				Projectiles.ballisticDirection(origin, Vector3.new(0, 5, -400), def.projectileSpeed, def.arcGravity)
			expect(far.Y).toBeNear(math.sin(math.rad(45)), 0.01)
		end)

		it("un à-coup du serveur ne fait pas traverser un mur", function()
			local list = { Projectiles.new(Vector3.new(0, 5, 0), Vector3.new(0, 0, -250), 0, 300, 6, nil) }
			local hit
			Projectiles.step(list, 0.5, 0, world(-60), function(_p, position)
				hit = position
			end)
			expect(#list).toBe(0)
			expect(hit.Z).toBeNear(-60, 0.01)
		end)

		it("durée de vie dépassée : le projectile disparaît", function()
			local list = { Projectiles.new(Vector3.new(0, 5, 0), Vector3.new(0, 0, -1), 0, 300, 2, nil) }
			local ended = 0
			Projectiles.step(list, 1 / 60, 3, world(nil), function()
				ended += 1
			end)
			expect(#list).toBe(0)
			expect(ended).toBe(1)
		end)
	end)

	describe("Parade", function()
		local function input(overrides)
			local base = { parrying = true, parryStartedAt = 0, now = 0.1, frontal = true, breaksParry = false }
			for k, v in overrides or {} do
				base[k] = v
			end
			return base
		end

		it("parade parfaite dans les 0,25 s", function()
			expect(Damage.resolveParry(input())).toBe("perfect")
			expect(Damage.parryMultiplier("perfect")).toBe(0)
		end)

		it("garde normale : -60 % de face", function()
			expect(Damage.resolveParry(input({ now = 1 }))).toBe("reduced")
			expect(Damage.parryMultiplier("reduced")).toBeNear(0.4)
		end)

		it("de dos ou sans garde : dégâts pleins", function()
			expect(Damage.resolveParry(input({ frontal = false }))).toBe("none")
			expect(Damage.resolveParry(input({ parrying = false }))).toBe("none")
		end)

		it("le marteau brise la garde", function()
			expect(Damage.resolveParry(input({ breaksParry = true }))).toBe("broken")
			expect(Damage.parryMultiplier("broken")).toBe(1)
		end)

		it("détection de face", function()
			local look = Vector3.new(0, 0, -1)
			local pos = Vector3.new(0, 0, 0)
			expect(Damage.isFrontal(look, pos, Vector3.new(0, 0, -5))).toBe(true)
			expect(Damage.isFrontal(look, pos, Vector3.new(0, 0, 5))).toBe(false)
			expect(Damage.isFrontal(look, pos, Vector3.new(5, 0, -5))).toBe(true) -- 45°
			expect(Damage.isFrontal(look, pos, Vector3.new(5, 0, 0))).toBe(false) -- 90°
		end)
	end)

	describe("WeaponLogic", function()
		it("chargeur : tir, cadence, vide, recharge", function()
			local def = W.scrap_laser_pistol
			local s = WeaponLogic.new(def)
			expect(s.ammo).toBe(12)
			expect(WeaponLogic.canFire(def, s, 0, 30)).toBe(true)
			local r = WeaponLogic.fire(def, s, 0)
			expect(r.projectiles).toBe(1)
			expect(s.ammo).toBe(11)
			local ok, why = WeaponLogic.canFire(def, s, 0.1, 30)
			expect(ok).toBe(false)
			expect(why).toBe("cooldown")
			expect(WeaponLogic.canFire(def, s, 0.34, 30)).toBe(true)
			-- Tolérance serveur (×0,85).
			expect(WeaponLogic.canFire(def, s, 0.29, 30, 0.85)).toBe(true)
			s.ammo = 0
			ok, why = WeaponLogic.canFire(def, s, 10, 30)
			expect(why).toBe("empty")
			expect(WeaponLogic.canReload(def, s, 30)).toBe(true)
			expect(WeaponLogic.canReload(def, s, 0)).toBe(false)
			WeaponLogic.startReload(def, s, 10)
			ok, why = WeaponLogic.canFire(def, s, 10.5, 30)
			expect(why).toBe("reloading")
			expect(WeaponLogic.finishReload(def, s, 11, 30)).toBe(0) -- pas encore fini
			expect(WeaponLogic.finishReload(def, s, 11.6, 5)).toBe(5) -- seulement 5 cellules
			expect(s.ammo).toBe(5)
			expect(s.reloadEndsAt).toBeNil()
		end)

		it("rafale : 3 projectiles par activation (limité par le chargeur)", function()
			local def = W.vigil_pistol
			local s = WeaponLogic.new(def)
			expect(WeaponLogic.fire(def, s, 0).projectiles).toBe(3)
			expect(s.ammo).toBe(21)
			s.ammo = 2
			expect(WeaponLogic.fire(def, s, 1).projectiles).toBe(2)
			expect(s.ammo).toBe(0)
		end)

		it("fusil à pompe : 8 plombs", function()
			local def = W.hullbreaker
			local s = WeaponLogic.new(def)
			expect(WeaponLogic.fire(def, s, 0).projectiles).toBe(8)
			expect(s.ammo).toBe(5)
		end)

		it("surchauffe : mitrailleuse, 1 cellule / 3 tirs, blocage 2,5 s", function()
			local def = W.bastion_minigun
			local s = WeaponLogic.new(def)
			local cells = 0
			local time = 0
			local shots = 0
			while true do
				local ok = WeaponLogic.canFire(def, s, time, 100)
				if not ok then
					break
				end
				local r = WeaponLogic.fire(def, s, time)
				cells += r.cellsConsumed
				shots += 1
				time += 1 / def.fireRate
				if r.overheated then
					break
				end
			end
			expect(shots).toBe(25) -- 25 × 4 = 100 de chaleur
			expect(cells).toBe(8) -- floor(25 / 3)
			local ok, why = WeaponLogic.canFire(def, s, time + 1, 100)
			expect(why).toBe("overheated")
			-- Après le blocage, la chaleur redescend de 30/s.
			WeaponLogic.updateHeat(s, s.overheatedUntil + 1)
			expect(s.heat).toBeNear(70)
			expect(WeaponLogic.canFire(def, s, s.overheatedUntil + 1, 100)).toBe(true)
		end)

		it("refroidissement seulement après 0,4 s sans tirer", function()
			local def = W.short_circuit
			local s = WeaponLogic.new(def)
			WeaponLogic.fire(def, s, 0)
			expect(s.heat).toBe(35)
			WeaponLogic.updateHeat(s, 0.3)
			expect(s.heat).toBe(35)
			WeaponLogic.updateHeat(s, 1.4)
			expect(s.heat).toBeNear(5)
		end)

		it("pas de tir sans cellules (armes à surchauffe)", function()
			local def = W.short_circuit
			local s = WeaponLogic.new(def)
			local ok, why = WeaponLogic.canFire(def, s, 0, 1)
			expect(ok).toBe(false)
			expect(why).toBe("no_cells")
			expect(WeaponLogic.canFire(def, s, 0, 2)).toBe(true)
			expect(WeaponLogic.fire(def, s, 0).cellsConsumed).toBe(2)
		end)
	end)

	describe("Rafale espacée", function()
		it("Vigil : trois projectiles à burstInterval d'écart", function()
			local def = W.vigil_pistol
			local schedule = WeaponLogic.burstSchedule(def)
			expect(#schedule).toBe(def.burstCount)
			expect(schedule[1]).toBe(0)
			for index = 2, #schedule do
				expect(schedule[index] - schedule[index - 1]).toBeNear(def.burstInterval)
			end
			expect(def.burstInterval > 0).toBe(true)
		end)

		it("arme sans rafale : un seul tir immédiat ; chargeur presque vide : rafale tronquée", function()
			local single = WeaponLogic.burstSchedule(W.sentinel_rifle)
			expect(#single).toBe(1)
			expect(single[1]).toBe(0)
			expect(#WeaponLogic.burstSchedule(W.vigil_pistol, 2)).toBe(2)
			expect(#WeaponLogic.burstSchedule(W.vigil_pistol, 0)).toBe(1)
		end)
	end)

	describe("Movement", function()
		local function state(overrides)
			local base = { stance = "stand", sprinting = false, parrying = false, stunned = false, speedMultiplier = 1 }
			for k, v in overrides or {} do
				base[k] = v
			end
			return base
		end

		it("vitesses du document (section 5.2)", function()
			expect(Movement.walkSpeed(state())).toBe(14)
			expect(Movement.walkSpeed(state({ sprinting = true }))).toBe(22)
			expect(Movement.walkSpeed(state({ stance = "crouch" }))).toBe(8)
			expect(Movement.walkSpeed(state({ stance = "prone" }))).toBe(4)
			expect(Movement.walkSpeed(state({ stance = "crouch", sprinting = true }))).toBe(8)
			expect(Movement.walkSpeed(state({ parrying = true }))).toBe(7)
			expect(Movement.walkSpeed(state({ sprinting = true, parrying = true }))).toBe(7)
			expect(Movement.walkSpeed(state({ speedMultiplier = 1.2 }))).toBeNear(16.8)
		end)

		it("pas de saut couché", function()
			expect(Movement.jumpHeight(state())).toBe(7)
			expect(Movement.jumpHeight(state({ stance = "prone" }))).toBe(0)
		end)

		it("précision : +15 % accroupi, +30 % couché", function()
			expect(Movement.spread(10, "stand", false, false)).toBeNear(10)
			expect(Movement.spread(10, "crouch", false, false)).toBeNear(8.5)
			expect(Movement.spread(10, "prone", false, false)).toBeNear(7)
		end)
	end)

	describe("HitValidator", function()
		local shooter = { name = "shooter" }
		local target = { name = "target" }
		local head = { Name = "Head", Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, 1.5, -50) }
		local torso = { Name = "UpperTorso", Size = Vector3.new(2, 1.6, 1), Position = Vector3.new(0, 0, -50) }
		local parts = { [head] = target, [torso] = target }

		local function context(overrides)
			local base = {
				now = 100,
				shooterHead = Vector3.new(0, 1.5, 0),
				effectiveRange = 60,
				maxProjectiles = 1,
				findTarget = function(part)
					return parts[part]
				end,
				shooter = shooter,
				castRay = function()
					return nil
				end,
			}
			for k, v in overrides or {} do
				base[k] = v
			end
			return base
		end

		local function shot(hits, overrides)
			local base = {
				t = 99.95,
				origin = Vector3.new(0, 1.5, 0),
				direction = Vector3.new(0, 0, -1),
				hits = hits,
			}
			for k, v in overrides or {} do
				base[k] = v
			end
			return base
		end

		it("tir valide à la tête", function()
			local v = HitValidator.validate(shot({ { part = head, position = Vector3.new(0, 1.5, -49.5) } }), context())
			expect(v.ok).toBe(true)
			expect(#v.hits).toBe(1)
			expect(v.hits[1].isHead).toBe(true)
			expect(v.hits[1].distance).toBeNear(49.5)
		end)

		it("rejette un tir trop ancien ou daté dans le futur", function()
			expect(HitValidator.validate(shot({}, { t = 98 }), context()).ok).toBe(false)
			expect(HitValidator.validate(shot({}, { t = 101 }), context()).ok).toBe(false)
		end)

		it("rejette une position de tireur incohérente", function()
			local v = HitValidator.validate(shot({}, { origin = Vector3.new(0, 1.5, 30) }), context())
			expect(v.ok).toBe(false)
		end)

		it("rejette trop d'impacts", function()
			local claim = { part = torso, position = Vector3.new(0, 0, -49.5) }
			expect(HitValidator.validate(shot({ claim, claim }), context()).ok).toBe(false)
			expect(HitValidator.validate(shot({ claim, claim }), context({ maxProjectiles = 8 })).ok).toBe(true)
		end)

		it("rejette un impact hors de portée ou loin de la cible", function()
			local far = { Name = "UpperTorso", Size = Vector3.new(2, 2, 1), Position = Vector3.new(0, 0, -400) }
			parts[far] = target
			local v = HitValidator.validate(shot({ { part = far, position = Vector3.new(0, 0, -400) } }), context())
			expect(v.ok).toBe(false)
			v = HitValidator.validate(shot({ { part = torso, position = Vector3.new(0, 0, -20) } }), context())
			expect(v.ok).toBe(false)
		end)

		it("ligne de vue bloquée : impact écarté sans sanction", function()
			local v = HitValidator.validate(
				shot({ { part = torso, position = Vector3.new(0, 0, -49.5) } }),
				context({
					castRay = function()
						return 20
					end,
				})
			)
			expect(v.ok).toBe(true)
			expect(#v.hits).toBe(0)
			expect(v.dropped).toBe(1)
		end)

		it("origine du tir derrière un obstacle : impacts écartés", function()
			local v = HitValidator.validate(
				shot({ { part = torso, position = Vector3.new(0, 0, -49.5) } }, { origin = Vector3.new(6, 1.5, 0) }),
				context({
					castRay = function(origin, displacement)
						-- Mur entre la tête (x = 0) et l'origine déclarée (x = 6).
						if displacement.X > 0 and origin.X == 0 then
							return 3
						end
						return nil
					end,
				})
			)
			expect(v.ok).toBe(true)
			expect(#v.hits).toBe(0)
			expect(v.dropped).toBe(1)
		end)

		it("impact hors de l'axe du tir (derrière, sur le côté) : refusé", function()
			local behind = { Name = "UpperTorso", Size = Vector3.new(2, 1.6, 1), Position = Vector3.new(0, 1.5, 30) }
			local side = { Name = "UpperTorso", Size = Vector3.new(2, 1.6, 1), Position = Vector3.new(30, 1.5, -5) }
			parts[behind] = target
			parts[side] = target
			local ctx = context({ maxSpread = 5 })
			local v = HitValidator.validate(shot({ { part = behind, position = Vector3.new(0, 1.5, 29.5) } }), ctx)
			expect(v.ok).toBe(false)
			v = HitValidator.validate(shot({ { part = side, position = Vector3.new(29.5, 1.5, -5) } }), ctx)
			expect(v.ok).toBe(false)
			parts[behind] = nil
			parts[side] = nil
		end)

		it("impact dans le cône de dispersion (et sa marge) : accepté", function()
			local V = Config.Combat.validation
			local spread = 5
			-- Juste à l'intérieur du cône élargi par la marge, à 50 studs.
			local inside = math.rad(spread + V.directionTolerance - 0.5)
			local torsoWide = { Name = "UpperTorso", Size = Vector3.new(12, 2, 1), Position = Vector3.new(0, 1.5, -50) }
			parts[torsoWide] = target
			local position = Vector3.new(math.tan(inside) * 50, 1.5, -50)
			local v = HitValidator.validate(
				shot({ { part = torsoWide, position = position } }),
				context({ maxSpread = spread })
			)
			expect(v.ok).toBe(true)
			expect(#v.hits).toBe(1)
			-- Juste au-delà : refusé.
			local outside = math.rad(spread + V.directionTolerance + 0.5)
			v = HitValidator.validate(
				shot({ { part = torsoWide, position = Vector3.new(math.tan(outside) * 50, 1.5, -50) } }),
				context({ maxSpread = spread })
			)
			expect(v.ok).toBe(false)
			parts[torsoWide] = nil
		end)

		it("dispersion maximale réelle : chaque arme accepte ses propres tirs, plombs compris", function()
			local Movement2 = H.require("ReplicatedStorage/Shared/Combat/Movement")
			for _, def in W do
				local worst = Movement2.spread(def.spread, "stand", false, true, true)
				-- Le tir le plus dévié que le client puisse produire, à 40 studs.
				local angle = math.rad(worst)
				local wide =
					{ Name = "UpperTorso", Size = Vector3.new(200, 200, 1), Position = Vector3.new(0, 1.5, -40) }
				parts[wide] = target
				local position = Vector3.new(math.sin(angle) * 40, 1.5, -math.cos(angle) * 40)
				local v = HitValidator.validate(
					shot({ { part = wide, position = position } }),
					context({ maxSpread = worst, effectiveRange = 200 })
				)
				expect(v.ok).toBe(true)
				parts[wide] = nil
			end
		end)

		it("cible au contact : pas de contrôle d'angle", function()
			local close = { Name = "UpperTorso", Size = Vector3.new(2, 1.6, 1), Position = Vector3.new(0.8, 1.5, 0.6) }
			parts[close] = target
			local v = HitValidator.validate(
				shot({ { part = close, position = Vector3.new(0.8, 1.5, 0.6) } }),
				context({ maxSpread = 1 })
			)
			expect(v.ok).toBe(true)
			parts[close] = nil
		end)

		it("ignore le tireur lui-même et les pièces sans propriétaire", function()
			local own = { Name = "Head", Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, 1.5, 0) }
			parts[own] = shooter
			local stray = { Name = "Wall", Size = Vector3.new(4, 4, 4), Position = Vector3.new(0, 0, -10) }
			local v = HitValidator.validate(
				shot({ { part = own, position = Vector3.new(0, 1.5, 0) } }, {}),
				context({ maxProjectiles = 2 })
			)
			expect(#v.hits).toBe(0)
			v = HitValidator.validate(shot({ { part = stray, position = Vector3.new(0, 0, -10) } }), context())
			expect(#v.hits).toBe(0)
		end)
	end)

	describe("Fighter", function()
		it("réserve de cellules", function()
			local inv = Fighter.simpleInventory({ cell_light = 40 })
			expect(inv:countCells("cell_light")).toBe(40)
			expect(inv:takeCells("cell_light", 12)).toBe(12)
			expect(inv:takeCells("cell_light", 100)).toBe(28)
			expect(inv:countCells("cell_light")).toBe(0)
			expect(inv:takeCells("cell_heavy", 5)).toBe(0)
		end)
	end)

	describe("Détente pendant un rechargement", function()
		it("seule la cadence garde un appui en attente", function()
			expect(WeaponLogic.keepsTrigger("cooldown")).toBe(true)
			for _, block in { "reloading", "overheated", "no_cells", "empty" } do
				expect(WeaponLogic.keepsTrigger(block)).toBe(false)
			end
			expect(Config.Combat.movement.triggerBuffer > Config.Combat.movement.sprintToFireDelay).toBe(true)
		end)

		it("un appui pendant le rechargement est refusé pour « rechargement » (donc oublié)", function()
			local def = W.scrap_laser_pistol
			local state = WeaponLogic.new(def, 0)
			state.ammo = 0
			WeaponLogic.startReload(def, state, 0)
			local ok, block = WeaponLogic.canFire(def, state, 0.5, 100)
			expect(ok).toBe(false)
			expect(block).toBe("reloading")
			expect(WeaponLogic.keepsTrigger(block)).toBe(false)
		end)
	end)

	describe("Armes contre les robots", function()
		local Robots = Config.Robots.byId
		local Modes = Config.Modes.byId
		-- Tirs nécessaires pour détruire un robot (arme dans son état, mode de jeu, à bout portant).
		local function shots(weaponId, condition, robotId, modeId)
			local hit = { def = W[weaponId], condition = condition, distance = 5, isHead = false, targetKind = "robot" }
			local health = Robots[robotId].health * Modes[modeId].robots.health
			return math.ceil(health / (Damage.ranged(hit) * W[weaponId].pellets))
		end

		it("le pistolet du kit de base a un bonus contre les robots, nettement sous l'arme de référence", function()
			local kit = Config.Economy.baseKit.ranged
			local pistol = W[kit.itemId].robotDamageMultiplier
			expect(pistol ~= nil).toBe(true)
			expect(pistol > 1).toBe(true)
			expect(pistol <= W.short_circuit.robotDamageMultiplier - 0.5).toBe(true)
			expect(W.short_circuit.robotDamageMultiplier).toBe(2.5)
		end)

		it("kit de base : robots légers et moyens en un chargeur, lourds et Gardien jamais triviaux", function()
			local kit = Config.Economy.baseKit.ranged
			local capacity = W[kit.itemId].capacity
			for _, modeId in { "easy", "medium" } do
				expect(shots(kit.itemId, kit.condition, "stalker", modeId) <= 5).toBe(true)
				expect(shots(kit.itemId, kit.condition, "sentinel", modeId) <= capacity).toBe(true)
			end
			-- Bastion : au moins deux chargeurs (sauf en visant son point faible) ; Gardien : un vrai combat.
			expect(shots(kit.itemId, kit.condition, "bastion", "medium") >= capacity * 2).toBe(true)
			expect(shots(kit.itemId, kit.condition, "warden", "easy") >= 40).toBe(true)
			expect(shots(kit.itemId, kit.condition, "warden", "medium") >= 60).toBe(true)
		end)

		it("bonus dégressif avec la valeur : l'équipement acheté reste plus fort par seconde", function()
			local previous = math.huge
			local ids = {}
			for id, def in W do
				if def.robotDamageMultiplier and id ~= "short_circuit" then
					table.insert(ids, id)
				end
			end
			table.sort(ids, function(a, b)
				return W[a].baseValue < W[b].baseValue
			end)
			for _, id in ids do
				expect(W[id].robotDamageMultiplier <= previous).toBe(true)
				previous = W[id].robotDamageMultiplier
			end
			-- Dégâts par seconde contre un robot : Fusil Sentinelle (bon état) > pistolet du kit.
			local function dps(id, condition)
				local hit = { def = W[id], condition = condition, distance = 5, isHead = false, targetKind = "robot" }
				return Damage.ranged(hit) * W[id].pellets * W[id].burstCount * W[id].fireRate
			end
			expect(dps("sentinel_rifle", 3) > dps("scrap_laser_pistol", 1) * 2).toBe(true)
		end)
	end)

	describe("Saut et lunette", function()
		local M = Config.Combat.movement
		it("en l'air, les tirs partent de travers, même accroupi et en visant", function()
			for _, def in W do
				local ground = Movement.spread(def.spread, "stand", false, false, false)
				local air = Movement.spread(def.spread, "crouch", true, false, true)
				expect(air).toBeNear(def.spread * M.airborneSpreadMultiplier + M.airborneSpreadBonus)
				expect(air >= ground + M.airborneSpreadBonus - 1e-6).toBe(true)
			end
			-- Même l'arme la plus précise devient imprécise en sautant.
			expect(Movement.spread(W.needle.spread, "stand", true, false, true) >= M.airborneSpreadBonus).toBe(true)
		end)

		it("l'Aiguille a une lunette qui zoome et resserre la dispersion", function()
			local scope = W.needle.scope
			expect(scope ~= nil).toBe(true)
			expect(scope.fieldOfView < Config.Combat.camera.aimFieldOfView).toBe(true)
			expect(scope.spreadMultiplier > 0 and scope.spreadMultiplier < 1).toBe(true)
			expect(Config.Combat.camera.scopeTransitionTime > 0).toBe(true)
		end)
	end)

	describe("Fiche de détail des armes", function()
		local WeaponStats = H.require("ReplicatedStorage/Shared/Combat/WeaponStats")
		local Localization = H.require("ReplicatedStorage/Shared/Localization")
		local all = {}
		for id in W do
			table.insert(all, id)
		end
		for id in Config.Weapons.melee do
			table.insert(all, id)
		end

		it("chaque arme a une fiche complète, des barres entre 0 et 1, une rareté", function()
			for _, id in all do
				local sheet = WeaponStats.sheet(id, 4)
				expect(sheet ~= nil).toBe(true)
				expect(#sheet.lines >= 4).toBe(true)
				for _, line in sheet.lines do
					if line.ratio then
						expect(line.ratio >= 0 and line.ratio <= 1 + 1e-6).toBe(true)
					end
				end
				expect(Config.Monetization.rarityColors[sheet.rarity] ~= nil).toBe(true)
			end
			expect(WeaponStats.sheet("helmet")).toBeNil()
			expect(table.find(WeaponStats.sheet("needle").traits, "scope") ~= nil).toBe(true)
		end)

		it("effet de l'état : 70 % (Très abîmé, −30 %) à 115 % (Neuf), référence = bon état", function()
			local effects = WeaponStats.conditionEffects(1)
			expect(#effects).toBe(Config.Conditions.MAX)
			expect(effects[1].percent).toBe(70)
			expect(effects[1].delta).toBe(-30)
			expect(effects[1].current).toBe(true)
			expect(effects[Config.Conditions.GOOD].delta).toBe(0)
			expect(effects[Config.Conditions.PRISTINE].percent).toBe(115)
			-- Les dégâts de la fiche suivent bien ce pourcentage.
			local wrecked = WeaponStats.sheet("sentinel_rifle", 1).lines[1].value
			local good = WeaponStats.sheet("sentinel_rifle", Config.Conditions.GOOD).lines[1].value
			expect(wrecked / good).toBeNear(0.70, 0.02)
			for _, effect in WeaponStats.conditionEffects(nil) do
				expect(effect.current).toBe(false)
			end
		end)

		it("place dans le sac : la valeur de l'arme, sans barre, qualifiée dans sa catégorie", function()
			local ItemRules = H.require("ReplicatedStorage/Shared/Items/ItemRules")
			for _, id in all do
				local sheet = WeaponStats.sheet(id, 4)
				local space = nil
				for _, line in sheet.lines do
					if line.key == "space" then
						space = line
					end
				end
				expect(space ~= nil).toBe(true)
				expect(space.value).toBe(ItemRules.up({ uid = "x", itemId = id, condition = 4 }))
				-- Pas de barre : plus long voudrait dire « mieux », or moins de place vaut mieux.
				expect(space.ratio).toBeNil()
				for _, lang in { "fr", "en" } do
					expect(Localization.has(lang, space.text)).toBe(true)
				end
			end
			-- Pistolet (2 UP) léger, Mitrailleuse de Bastion (6 UP) encombrante.
			local function tierOf(id)
				for _, line in WeaponStats.sheet(id, 4).lines do
					if line.key == "space" then
						return line.text
					end
				end
				return nil
			end
			expect(tierOf("vigil_pistol")).toBe("weapon.value.space.light")
			expect(tierOf("bastion_minigun")).toBe("weapon.value.space.bulky")
		end)

		it("rareté croissante avec la valeur ; précision cohérente avec la dispersion", function()
			local order = {}
			for index, step in Config.Weapons.rarityByValue do
				order[step.rarity] = index
			end
			for _, a in all do
				for _, b in all do
					local va = (W[a] or Config.Weapons.melee[a]).baseValue
					local vb = (W[b] or Config.Weapons.melee[b]).baseValue
					if va < vb then
						expect(order[WeaponStats.rarity(a)] <= order[WeaponStats.rarity(b)]).toBe(true)
					end
				end
			end
			expect(WeaponStats.precision(0)).toBe(100)
			expect(WeaponStats.precision(Config.Weapons.precisionSpreadZero)).toBe(0)
			expect(WeaponStats.precision(W.needle.spread) > WeaponStats.precision(W.hullbreaker.spread)).toBe(true)
		end)

		it("l'état de l'arme change les dégâts affichés", function()
			local worn = WeaponStats.sheet("sentinel_rifle", 1).lines[1].value
			local pristine = WeaponStats.sheet("sentinel_rifle", 5).lines[1].value
			expect(pristine > worn).toBe(true)
		end)

		it("tous les textes de la fiche existent en FR et en EN", function()
			for _, lang in { "fr", "en" } do
				for _, id in all do
					expect(Localization.has(lang, "item." .. id .. ".desc")).toBe(true)
					local sheet = WeaponStats.sheet(id, 4)
					expect(Localization.has(lang, "weapon.category." .. sheet.category)).toBe(true)
					for _, line in sheet.lines do
						expect(Localization.has(lang, "weapon.stat." .. line.key)).toBe(true)
						expect(Localization.has(lang, line.text)).toBe(true)
					end
					for _, trait in sheet.traits do
						expect(Localization.has(lang, "weapon.trait." .. trait)).toBe(true)
					end
				end
			end
		end)
	end)

	describe("Visée assistée (AimAssist)", function()
		local roblox = require("@lune/roblox")
		local Vector3 = roblox.Vector3
		local AimAssist = H.require("ReplicatedStorage/Shared/Combat/AimAssist")
		local A = H.require("ReplicatedStorage/Shared/Config").Combat.aimAssist
		local origin, look = Vector3.new(0, 0, 0), Vector3.new(0, 0, -1)

		-- Point à `distance` studs, décalé de `degrees` du centre de l'écran.
		local function at(degrees, distance, id)
			local r = math.rad(degrees)
			return { point = Vector3.new(math.sin(r), 0, -math.cos(r)) * distance, model = id }
		end

		it("jamais à la souris ; désactivable ; force bornée à [0, 1]", function()
			expect(AimAssist.strength("keyboard", true, 1)).toBe(0)
			expect(AimAssist.strength("gamepad", false, 1)).toBe(0)
			expect(AimAssist.strength("touch", true, 0.5)).toBe(0.5)
			expect(AimAssist.strength("gamepad", true, 3)).toBe(1)
		end)

		it("cible : dans le cône de 6° et à portée, la plus proche du centre", function()
			expect(A.cone).toBe(6)
			expect(AimAssist.pick(origin, look, { at(A.cone + 0.5, 50, "hors cône") })).toBeNil()
			expect(AimAssist.pick(origin, look, { at(0, A.range + 1, "trop loin") })).toBeNil()
			expect(AimAssist.pick(origin, look, { at(0, 0.5, "collé") })).toBeNil()
			local best = AimAssist.pick(origin, look, { at(4, 30, "a"), at(1, 120, "b"), at(-2.5, 60, "c") })
			expect(best.model).toBe("b")
		end)

		it("ralentissement : 45 % au maximum, rien sans cible", function()
			expect(AimAssist.slowdown(1, false)).toBe(1)
			expect(AimAssist.slowdown(1, true)).toBeNear(1 - 0.45, 1e-9)
			expect(AimAssist.slowdown(0.5, true)).toBeNear(1 - 0.45 * 0.5, 1e-9)
		end)

		it("adhérence : au plus 7°/s × force, par le plus court chemin", function()
			local maxPitch = math.rad(80)
			-- Cible loin à droite : le pas est borné.
			local direction = Vector3.new(math.sin(math.rad(-90)), 0, -math.cos(math.rad(-90)))
			local yaw = AimAssist.pull(0, 0, direction, 1, 1, maxPitch)
			expect(math.abs(math.deg(yaw))).toBeNear(A.pull, 1e-6)
			yaw = AimAssist.pull(0, 0, direction, 0.5, 0.1, maxPitch)
			expect(math.abs(math.deg(yaw))).toBeNear(A.pull * 0.5 * 0.1, 1e-6)
			-- Cible presque atteinte : on s'arrête dessus, sans la dépasser.
			local near = Vector3.new(math.sin(math.rad(-0.01)), 0, -math.cos(math.rad(-0.01)))
			local yawNear = AimAssist.pull(0, 0, near, 1, 1, maxPitch)
			expect(math.abs(math.deg(yawNear))).toBeNear(0.01, 1e-6)
			-- Lacet à 179° et cible à -179° : 2° de rotation, pas 358.
			local behind = Vector3.new(-math.sin(math.rad(-179)), 0, -math.cos(math.rad(-179)))
			local start = math.rad(179)
			local next = AimAssist.pull(start, 0, behind, 1, 10, maxPitch)
			local moved = (next - start + math.pi) % (2 * math.pi) - math.pi
			expect(math.abs(math.deg(moved))).toBeNear(2, 1e-6)
		end)
	end)

	describe("Contrôle des déplacements (MovementCheck)", function()
		local roblox = require("@lune/roblox")
		local Vector3, CFrame = roblox.Vector3, roblox.CFrame
		local MovementCheck = H.require("ServerScriptService/Server/Combat/MovementCheck")
		local Movement = H.require("ReplicatedStorage/Shared/Combat/Movement")
		local Config = H.require("ReplicatedStorage/Shared/Config")
		local G = Config.Combat.movementGuard
		local M = Config.Combat.movement
		local GRAVITY = 196.2 -- gravité par défaut de Roblox
		local DT = G.interval

		local function state(overrides)
			local s = { stance = "stand", sprinting = false, parrying = false, stunned = false, speedMultiplier = 1 }
			for k, v in overrides or {} do
				s[k] = v
			end
			return s
		end

		-- Piste neuve, sortie de la seconde de grâce d'apparition (clock = 2).
		local function track(at)
			local t = MovementCheck.newTrack(CFrame.new(at or Vector3.new(0, 0, 0)), 0)
			return t, 2
		end

		-- `steps` contrôles à `speed` studs/s (+ `rise` studs de montée par contrôle).
		local function run(t, clock, from, speed, steps, baseSpeed, rise)
			local verdicts, position = {}, from
			for _ = 1, steps do
				clock += DT
				position += Vector3.new(speed * DT, rise or 0, 0)
				table.insert(verdicts, (MovementCheck.step(t, CFrame.new(position), clock, DT, baseSpeed, false)))
			end
			return verdicts, clock, position
		end

		local function count(verdicts, kind)
			local n = 0
			for _, v in verdicts do
				if v == kind then
					n += 1
				end
			end
			return n
		end

		it("joueur honnête : marche, sprint, sprint sous Surcharge, accroupi → jamais d'infraction", function()
			local surcharge = Config.Equipment.consumables.overdrive.effect.speedMultiplier
			for _, s in
				{
					state(),
					state({ sprinting = true }),
					state({ sprinting = true, speedMultiplier = surcharge }),
					state({ stance = "crouch" }),
				}
			do
				local t, clock = track()
				local speed = Movement.walkSpeed(s)
				local verdicts = run(t, clock, Vector3.new(0, 0, 0), speed, 40, speed)
				expect(count(verdicts, "ok")).toBe(40)
			end
		end)

		it("fin de sprint : l'ancienne vitesse reste admise le temps de la latence", function()
			local t, clock = track()
			local sprint = Movement.walkSpeed(state({ sprinting = true }))
			local verdicts, position
			verdicts, clock, position = run(t, clock, Vector3.new(0, 0, 0), sprint, 4, sprint)
			MovementCheck.speedChanged(t, sprint, clock)
			-- Le serveur passe à la marche ; le client sprinte encore un instant.
			MovementCheck.speedChanged(t, M.walkSpeed, clock)
			verdicts, clock, position = run(t, clock, position, sprint, 2, M.walkSpeed)
			expect(count(verdicts, "ok")).toBe(2)
			-- Au-delà du délai de grâce, sprinter en marchant finit en recalage.
			verdicts = run(t, clock + G.speedGraceTime, position, sprint * 1.6, 3, M.walkSpeed)
			expect(count(verdicts, "correct") >= 1).toBe(true)
		end)

		it("latence : paquets regroupés et pic d'1 s rattrapés d'un coup → jamais de recalage", function()
			local t, clock = track()
			local step = M.walkSpeed * DT
			local verdicts, position
			verdicts, clock, position = run(t, clock, Vector3.new(0, 0, 0), M.walkSpeed, 4, M.walkSpeed)
			local all = {}
			local function at(p)
				clock += DT
				table.insert(all, (MovementCheck.step(t, CFrame.new(p), clock, DT, M.walkSpeed, false)))
			end
			-- Un intervalle sans nouvelles, puis deux d'un coup.
			at(position)
			position += Vector3.new(2 * step, 0, 0)
			at(position)
			-- Pic d'une seconde (4 contrôles immobiles), puis tout le trajet d'un coup.
			for _ = 1, 4 do
				at(position)
			end
			position += Vector3.new(5 * step, 0, 0)
			at(position)
			for _ = 1, 4 do
				position += Vector3.new(step, 0, 0)
				at(position)
			end
			expect(count(all, "correct")).toBe(0)
			expect(count(verdicts, "ok")).toBe(4)
		end)

		it("téléportation unique (même courte) recalée à la dernière position valide", function()
			for _, distance in { 30, 120 } do
				local t, clock = track()
				local _, position
				_, clock, position = run(t, clock, Vector3.new(0, 0, 0), M.walkSpeed, 4, M.walkSpeed)
				local valid = t.lastValid.Position
				local far = position + Vector3.new(distance, 0, 0)
				clock += DT
				expect(MovementCheck.step(t, CFrame.new(far), clock, DT, M.walkSpeed, false)).toBe("strike")
				-- Le tricheur reste sur place (ou repart normalement) : rien ne la « blanchit ».
				clock += DT
				local verdict, reason =
					MovementCheck.step(t, CFrame.new(far + Vector3.new(1, 0, 0)), clock, DT, M.walkSpeed, false)
				expect(verdict).toBe("correct")
				expect(string.find(reason, "vitesse anormale", 1, true) ~= nil).toBe(true)
				expect((t.lastValid.Position - valid).Magnitude).toBeNear(0, 1e-6)
			end
		end)

		it("rester immobile n'ouvre qu'un crédit borné : grande téléportation ensuite recalée", function()
			local t, clock = track()
			local verdicts
			verdicts, clock = run(t, clock, Vector3.new(0, 0, 0), 0, 40, M.walkSpeed) -- 10 s immobile
			expect(count(verdicts, "ok")).toBe(40)
			local reach = M.walkSpeed * (G.catchUpWindow + DT) * G.speedTolerance + G.flatTolerance
			local far = Vector3.new(reach + 5, 0, 0)
			clock += DT
			expect(MovementCheck.step(t, CFrame.new(far), clock, DT, M.walkSpeed, false)).toBe("strike")
			clock += DT
			expect(MovementCheck.step(t, CFrame.new(far), clock, DT, M.walkSpeed, false)).toBe("correct")
		end)

		it("triche de vitesse continue (×2) : recalée", function()
			local t, clock = track()
			local verdicts = run(t, clock, Vector3.new(0, 0, 0), M.sprintSpeed * 2, 6, M.sprintSpeed)
			expect(count(verdicts, "correct") >= 2).toBe(true)
		end)

		it("montée : saut et escaliers admis, vol refusé ; chute jamais limitée", function()
			local t, clock = track()
			local verdicts = run(t, clock, Vector3.new(0, 0, 0), M.walkSpeed, 4, M.walkSpeed, G.maxVerticalRise)
			expect(count(verdicts, "ok")).toBe(4)
			t, clock = track()
			local reason
			clock += DT
			MovementCheck.step(t, CFrame.new(0, 30, 0), clock, DT, M.walkSpeed, false)
			clock += DT
			verdicts, reason = MovementCheck.step(t, CFrame.new(0, 60, 0), clock, DT, M.walkSpeed, false)
			expect(verdicts).toBe("correct")
			expect(reason).toBe("montée anormale")
			t, clock = track(Vector3.new(0, 500, 0))
			verdicts = run(t, clock, Vector3.new(0, 500, 0), 0, 6, M.walkSpeed, -80)
			expect(count(verdicts, "ok")).toBe(6)
		end)

		it("bottes de saut, grappin, repoussement du Gantelet : tolérance accordée puis retirée", function()
			-- Bottes de saut : montée de la hauteur du saut (GadgetService).
			local t, clock = track()
			local height = 30
			MovementCheck.grant(t, math.sqrt(2 * GRAVITY * height), 2.5, height + 4, clock)
			local verdicts = run(t, clock, Vector3.new(0, 0, 0), M.walkSpeed, 2, M.walkSpeed, height / 2)
			expect(count(verdicts, "ok")).toBe(2)
			-- Repoussement : vol plané latéral rapide.
			t, clock = track()
			local velocity = Vector3.new(80, 50, 0)
			local speed, duration, rise = MovementCheck.knockbackAllowance(velocity, 0.4, GRAVITY)
			expect(duration).toBeNear(1.0, 1e-9)
			MovementCheck.grant(t, speed, duration, rise, clock)
			verdicts, clock = run(t, clock, Vector3.new(0, 0, 0), 80, 3, M.walkSpeed, rise * 0.9)
			expect(count(verdicts, "ok")).toBe(3)
			-- Allocation échue : la même vitesse redevient une infraction.
			verdicts = run(t, clock + 2, Vector3.new(0, 0, 0), 80, 2, M.walkSpeed)
			expect(verdicts[2]).toBe("correct")
		end)

		it("apparition, téléportation serveur ou personnage ancré : aucun contrôle", function()
			local t = MovementCheck.newTrack(CFrame.new(0, 0, 0), 0)
			expect(MovementCheck.step(t, CFrame.new(500, 0, 0), 0.25, DT, M.walkSpeed, false)).toBe("ok")
			expect(MovementCheck.step(t, CFrame.new(900, 0, 0), 0.5, DT, M.walkSpeed, false)).toBe("ok")
			expect(MovementCheck.step(t, CFrame.new(1400, 0, 0), 5, DT, M.walkSpeed, true)).toBe("ok")
			expect(t.strikes).toBe(0)
			expect(t.lastValid.Position.X).toBe(1400)
		end)
	end)
end
