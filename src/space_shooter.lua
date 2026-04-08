local soluna = require "soluna"
local app = require "soluna.app"
local file = require "soluna.file"
local matquad = require "soluna.material.quad"
local mattext = require "soluna.material.text"
local font = require "soluna.font"
local util = require "utils"

math.randomseed(os.time())

local args = ...
local batch = args.batch

local W = 480
local H = 640

local MAX_STARS = 80
local MAX_BULLETS = 30
local MAX_ENEMIES = 20
local MAX_EXPLOSIONS = 15
local MAX_ENEMY_BULLETS = 20

local KEY_ESCAPE = 256
local KEY_LEFT = 263
local KEY_RIGHT = 262
local KEY_UP = 265
local KEY_DOWN = 264
local KEY_SPACE = 32
local KEY_R = 82
local KEYSTATE_RELEASE = 0
local KEYSTATE_PRESS = 1

local COLOR_WHITE = 0xffffffff
local COLOR_CYAN = 0xff00ffff
local COLOR_GRAY = 0xff909090
local COLOR_DARK_GRAY = 0xff505050
local COLOR_RED = 0xffff3030
local COLOR_ORANGE = 0xffff9000
local COLOR_YELLOW = 0xffffff40
local COLOR_GREEN = 0xff30ff30
local COLOR_MAGENTA = 0xffff40ff

local function clamp(v, min_v, max_v)
	if v < min_v then
		return min_v
	end
	if v > max_v then
		return max_v
	end
	return v
end

local function rect_overlap(ax, ay, aw, ah, bx, by, bw, bh)
	return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local function rgba(color)
	local a = color >> 24 & 0xff
	local r = color >> 16 & 0xff
	local g = color >> 8 & 0xff
	local b = color & 0xff
	return string.pack("BBBB", r, g, b, a)
end

local function create_canvas(width, height)
	local pixels = {}
	local clear = rgba(0)
	for i = 1, width * height do
		pixels[i] = clear
	end

	local canvas = {}

	function canvas.set_pixel(x, y, color)
		if x < 0 or x >= width or y < 0 or y >= height then
			return
		end
		pixels[y * width + x + 1] = rgba(color)
	end

	function canvas.to_content()
		return table.concat(pixels)
	end

	return canvas
end

local function create_player_content()
	local canvas = create_canvas(24, 24)

	for y = 4, 19 do
		for x = 9, 14 do
			canvas.set_pixel(x, y, COLOR_CYAN)
		end
	end

	for x = 10, 13 do
		canvas.set_pixel(x, 2, COLOR_WHITE)
		canvas.set_pixel(x, 3, COLOR_WHITE)
	end
	canvas.set_pixel(11, 0, COLOR_WHITE)
	canvas.set_pixel(12, 0, COLOR_WHITE)
	canvas.set_pixel(11, 1, COLOR_WHITE)
	canvas.set_pixel(12, 1, COLOR_WHITE)

	for x = 2, 8 do
		for y = 13, 16 do
			canvas.set_pixel(x, y, COLOR_GRAY)
		end
	end

	for x = 15, 21 do
		for y = 13, 16 do
			canvas.set_pixel(x, y, COLOR_GRAY)
		end
	end

	canvas.set_pixel(11, 20, COLOR_ORANGE)
	canvas.set_pixel(12, 20, COLOR_ORANGE)
	canvas.set_pixel(11, 21, COLOR_YELLOW)
	canvas.set_pixel(12, 21, COLOR_YELLOW)

	return canvas:to_content()
end

local function create_enemy_content(body_color)
	local canvas = create_canvas(20, 20)

	for y = 2, 13 do
		local half = 14 - y
		local cx = 10
		for x = cx - half, cx + half - 1 do
			canvas.set_pixel(x, y, body_color)
		end
	end

	for y = 3, 7 do
		canvas.set_pixel(1, y, COLOR_DARK_GRAY)
		canvas.set_pixel(18, y, COLOR_DARK_GRAY)
	end

	canvas.set_pixel(9, 5, COLOR_YELLOW)
	canvas.set_pixel(10, 5, COLOR_YELLOW)
	canvas.set_pixel(9, 6, COLOR_YELLOW)
	canvas.set_pixel(10, 6, COLOR_YELLOW)

	return canvas:to_content()
end

local function create_explosion_content(radius, outer_color, inner_color)
	local size = radius * 2 + 6
	local canvas = create_canvas(size, size)
	local cx = size // 2
	local cy = size // 2
	local inner_radius = math.max(radius - 3, 0)
	local outer_sq = radius * radius
	local inner_sq = inner_radius * inner_radius

	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local dx = x - cx
			local dy = y - cy
			local dist_sq = dx * dx + dy * dy
			if dist_sq <= outer_sq then
				if dist_sq <= inner_sq then
					canvas.set_pixel(x, y, inner_color)
				else
					canvas.set_pixel(x, y, outer_color)
				end
			end
		end
	end

	return canvas:to_content(), size, size
end

local function build_sprite_assets()
	local preload = {
		{
			filename = "@player",
			content = create_player_content(),
			w = 24,
			h = 24,
		},
		{
			filename = "@enemy_red",
			content = create_enemy_content(COLOR_RED),
			w = 20,
			h = 20,
		},
		{
			filename = "@enemy_magenta",
			content = create_enemy_content(COLOR_MAGENTA),
			w = 20,
			h = 20,
		},
	}

	local bundle = {
		{ name = "player",        filename = "@player" },
		{ name = "enemy_red",     filename = "@enemy_red" },
		{ name = "enemy_magenta", filename = "@enemy_magenta" },
	}

	local explosion_defs = {
		{ name = "exp_1", radius = 5,  outer = COLOR_WHITE,  inner = COLOR_RED },
		{ name = "exp_2", radius = 8,  outer = COLOR_WHITE,  inner = COLOR_RED },
		{ name = "exp_3", radius = 11, outer = COLOR_YELLOW, inner = COLOR_RED },
		{ name = "exp_4", radius = 14, outer = COLOR_ORANGE, inner = COLOR_RED },
		{ name = "exp_5", radius = 17, outer = COLOR_ORANGE, inner = COLOR_RED },
	}

	for _, def in ipairs(explosion_defs) do
		local content, width, height = create_explosion_content(def.radius, def.outer, def.inner)
		local filename = "@" .. def.name
		preload[#preload + 1] = {
			filename = filename,
			content = content,
			w = width,
			h = height,
		}
		bundle[#bundle + 1] = {
			name = def.name,
			filename = filename,
			x = -(width // 2),
			y = -(height // 2),
		}
	end

	soluna.preload(preload)
	return soluna.load_sprites(bundle)
end

soluna.set_window_title "Space Shooter"

local sprites = build_sprite_assets()
local fontid = util.font_init(soluna, font, file, {
	error_message = "No available system font for space_shooter",
})
local fontcobj = font.cobj()

local title_block = mattext.block(fontcobj, fontid, 32, COLOR_RED, "LT")
local body_block = mattext.block(fontcobj, fontid, 16, COLOR_WHITE, "LT")
local hint_block = mattext.block(fontcobj, fontid, 14, COLOR_DARK_GRAY, "LT")
local score_block = mattext.block(fontcobj, fontid, 16, COLOR_WHITE, "LT")
local lives_block = mattext.block(fontcobj, fontid, 16, COLOR_GREEN, "LT")
local level_block = mattext.block(fontcobj, fontid, 16, COLOR_YELLOW, "LT")

local label = util.label_cache()
local quad = util.quad_cache(matquad)
local view = util.fixed_view(args, W, H)

local stars = {}
for i = 1, MAX_STARS do
	local speed = math.random(1, 4)
	local brightness = math.min(255, 80 + speed * 40)
	stars[i] = {
		x = math.random(0, W - 1),
		y = math.random(0, H - 1),
		speed = speed,
		color = 0xff000000 | brightness << 16 | brightness << 8 | brightness,
	}
end

local bullets = {}
for i = 1, MAX_BULLETS do
	bullets[i] = { active = false, x = 0, y = 0 }
end

local enemies = {}
for i = 1, MAX_ENEMIES do
	enemies[i] = { active = false, x = 0, y = 0, vx = 0, vy = 0, hp = 0, type = 0 }
end

local enemy_bullets = {}
for i = 1, MAX_ENEMY_BULLETS do
	enemy_bullets[i] = { active = false, x = 0, y = 0, vy = 0 }
end

local explosions = {}
for i = 1, MAX_EXPLOSIONS do
	explosions[i] = { active = false, x = 0, y = 0, timer = 0 }
end

local keys_down = {}
local player_x = W / 2 - 12
local player_y = H - 60
local shoot_timer = 0
local spawn_timer = 0
local score = 0
local lives = 3
local level = 1
local kill_count = 0
local game_over = false
local invincible = 0

local function reset_game()
	player_x = W / 2 - 12
	player_y = H - 60
	shoot_timer = 0
	spawn_timer = 0
	score = 0
	lives = 3
	level = 1
	kill_count = 0
	game_over = false
	invincible = 0

	for _, bullet in ipairs(bullets) do
		bullet.active = false
	end
	for _, enemy in ipairs(enemies) do
		enemy.active = false
	end
	for _, bullet in ipairs(enemy_bullets) do
		bullet.active = false
	end
	for _, explosion in ipairs(explosions) do
		explosion.active = false
	end
end

local function spawn_player_bullet()
	for _, bullet in ipairs(bullets) do
		if not bullet.active then
			bullet.active = true
			bullet.x = player_x + 10
			bullet.y = player_y - 5
			return
		end
	end
end

local function spawn_enemy()
	for _, enemy in ipairs(enemies) do
		if not enemy.active then
			local enemy_type = math.random(0, 1)
			enemy.active = true
			enemy.x = math.random(10, W - 30)
			enemy.y = math.random(-80, -20)
			enemy.vx = math.random(-2, 2)
			enemy.vy = math.random(1, 2 + level // 2)
			enemy.type = enemy_type
			enemy.hp = enemy_type == 0 and 1 or 2
			return
		end
	end
end

local function spawn_enemy_bullet(enemy)
	for _, bullet in ipairs(enemy_bullets) do
		if not bullet.active then
			bullet.active = true
			bullet.x = enemy.x + 10
			bullet.y = enemy.y + 20
			bullet.vy = 4 + level * 0.5
			return
		end
	end
end

local function spawn_explosion(x, y)
	for _, explosion in ipairs(explosions) do
		if not explosion.active then
			explosion.active = true
			explosion.x = x
			explosion.y = y
			explosion.timer = 15
			return
		end
	end
end

local function apply_player_hit()
	lives = lives - 1
	invincible = 90
	if lives <= 0 then
		game_over = true
	end
end

local function update_stars()
	for _, star in ipairs(stars) do
		star.y = star.y + star.speed
		if star.y > H then
			star.y = 0
			star.x = math.random(0, W - 1)
		end
	end
end

local function update_game()
	if game_over then
		return
	end

	local speed = 5
	if keys_down[KEY_LEFT] then
		player_x = player_x - speed
	end
	if keys_down[KEY_RIGHT] then
		player_x = player_x + speed
	end
	if keys_down[KEY_UP] then
		player_y = player_y - speed
	end
	if keys_down[KEY_DOWN] then
		player_y = player_y + speed
	end

	player_x = clamp(player_x, 0, W - 24)
	player_y = clamp(player_y, 0, H - 24)

	if keys_down[KEY_SPACE] then
		shoot_timer = shoot_timer + 1
		if shoot_timer >= 6 then
			shoot_timer = 0
			spawn_player_bullet()
		end
	else
		shoot_timer = 5
	end

	for _, bullet in ipairs(bullets) do
		if bullet.active then
			bullet.y = bullet.y - 10
			if bullet.y < -10 then
				bullet.active = false
			end
		end
	end

	spawn_timer = spawn_timer + 1
	local rate = math.max(15, 50 - level * 5)
	if spawn_timer >= rate then
		spawn_timer = 0
		spawn_enemy()
	end

	for _, enemy in ipairs(enemies) do
		if enemy.active then
			enemy.x = enemy.x + enemy.vx
			enemy.y = enemy.y + enemy.vy

			if enemy.x < 0 or enemy.x > W - 20 then
				enemy.vx = -enemy.vx
				enemy.x = clamp(enemy.x, 0, W - 20)
			end

			if enemy.y > H + 20 then
				enemy.active = false
			elseif math.random(0, 200) < 1 + level then
				spawn_enemy_bullet(enemy)
			end
		end
	end

	for _, bullet in ipairs(enemy_bullets) do
		if bullet.active then
			bullet.y = bullet.y + bullet.vy
			if bullet.y > H + 10 then
				bullet.active = false
			end
		end
	end

	for _, bullet in ipairs(bullets) do
		if bullet.active then
			for _, enemy in ipairs(enemies) do
				if enemy.active and rect_overlap(bullet.x - 1, bullet.y - 4, 4, 8, enemy.x, enemy.y, 20, 20) then
					bullet.active = false
					enemy.hp = enemy.hp - 1
					if enemy.hp <= 0 then
						enemy.active = false
						score = score + (enemy.type + 1) * 100
						kill_count = kill_count + 1
						if kill_count >= 10 + level * 5 then
							level = level + 1
							kill_count = 0
						end
						spawn_explosion(enemy.x + 10, enemy.y + 10)
					end
					break
				end
			end
		end
	end

	if invincible > 0 then
		invincible = invincible - 1
	else
		for _, bullet in ipairs(enemy_bullets) do
			if bullet.active and rect_overlap(bullet.x - 2, bullet.y - 2, 4, 8, player_x + 4, player_y + 2, 16, 20) then
				bullet.active = false
				apply_player_hit()
				break
			end
		end

		if invincible == 0 then
			for _, enemy in ipairs(enemies) do
				if enemy.active and rect_overlap(enemy.x, enemy.y, 20, 20, player_x + 2, player_y + 2, 20, 20) then
					enemy.active = false
					apply_player_hit()
					break
				end
			end
		end
	end

	for _, explosion in ipairs(explosions) do
		if explosion.active then
			explosion.timer = explosion.timer - 1
			if explosion.timer <= 0 then
				explosion.active = false
			end
		end
	end
end

local function draw_stars()
	for _, star in ipairs(stars) do
		batch:add(quad { width = 1, height = 1, color = star.color }, star.x, star.y)
	end
end

local function draw_player_bullets()
	for _, bullet in ipairs(bullets) do
		if bullet.active then
			batch:add(quad { width = 3, height = 8, color = COLOR_YELLOW }, bullet.x, bullet.y - 4)
		end
	end
end

local function draw_enemy_bullets()
	for _, bullet in ipairs(enemy_bullets) do
		if bullet.active then
			batch:add(quad { width = 3, height = 6, color = COLOR_RED }, bullet.x - 1, bullet.y)
		end
	end
end

local function draw_enemies()
	for _, enemy in ipairs(enemies) do
		if enemy.active then
			local sprite = enemy.type == 0 and sprites.enemy_red or sprites.enemy_magenta
			batch:add(sprite, enemy.x, enemy.y)
		end
	end
end

local function draw_explosions()
	for _, explosion in ipairs(explosions) do
		if explosion.active then
			local index = clamp(6 - math.ceil(explosion.timer / 3), 1, 5)
			batch:add(sprites["exp_" .. index], explosion.x, explosion.y)
		end
	end
end

local function draw_player()
	if invincible == 0 or (invincible // 4) % 2 == 0 then
		batch:add(sprites.player, player_x, player_y)
	end
end

local function draw_hud()
	batch:add(label { block = score_block, text = string.format("SCORE: %d", score), width = 160, height = 20 }, 10, 10)
	batch:add(label { block = lives_block, text = string.format("LIVES: %d", lives), width = 100, height = 20 }, W - 100,
		10)
	batch:add(label { block = level_block, text = string.format("LV.%d", level), width = 60, height = 20 }, W / 2 - 30,
		10)
	batch:add(label { block = hint_block, text = "Arrows:Move  Space:Shoot", width = 240, height = 20 }, 10, H - 20)
end

local function draw_game_over()
	if not game_over then
		return
	end

	local panel_x = W / 2 - 120
	local panel_y = H / 2 - 50
	batch:add(quad { width = 240, height = 100, color = COLOR_DARK_GRAY }, panel_x, panel_y)
	batch:add(quad { width = 240, height = 2, color = COLOR_WHITE }, panel_x, panel_y)
	batch:add(quad { width = 240, height = 2, color = COLOR_WHITE }, panel_x, panel_y + 98)
	batch:add(quad { width = 2, height = 100, color = COLOR_WHITE }, panel_x, panel_y)
	batch:add(quad { width = 2, height = 100, color = COLOR_WHITE }, panel_x + 238, panel_y)

	batch:add(label { block = title_block, text = "GAME OVER", width = 160, height = 40 }, W / 2 - 65, H / 2 - 40)
	batch:add(label { block = body_block, text = string.format("Final Score: %d", score), width = 140, height = 20 },
		W / 2 - 55,
		H / 2)
	batch:add(label { block = body_block, text = string.format("Level: %d", level), width = 100, height = 20 },
		W / 2 - 45,
		H / 2 + 18)
	batch:add(label { block = level_block, text = "R to restart", width = 100, height = 20 }, W / 2 - 50, H / 2 + 36)
end

local callback = {}

function callback.frame()
	view.begin(batch)

	update_stars()
	update_game()

	draw_stars()
	draw_player_bullets()
	draw_enemy_bullets()
	draw_enemies()
	draw_explosions()
	draw_player()
	draw_hud()
	draw_game_over()

	view.finish(batch)
end

function callback.key(keycode, state)
	if state == KEYSTATE_RELEASE then
		keys_down[keycode] = false
		return
	end

	keys_down[keycode] = true

	if state == KEYSTATE_PRESS then
		if keycode == KEY_ESCAPE then
			app.quit()
		elseif keycode == KEY_R and game_over then
			reset_game()
		end
	end
end

function callback.window_resize(w, h)
	view.resize(w, h)
	player_x = clamp(player_x, 0, W - 24)
	player_y = clamp(player_y, 0, H - 24)
end

return callback
