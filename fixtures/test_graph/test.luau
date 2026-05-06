local function dumpTable(tbl, indent)
	indent = indent or 0
	for k, v in pairs(tbl) do
		print(string.rep(" ", indent) .. tostring(k) .. ":")
		if type(v) == "table" then
			dumpTable(v, indent + 2)
		else
			print(string.rep(" ", indent + 2) .. tostring(v))
		end
	end
end

local dt_acum = 0

function tick(world, ent, dt)
	dt_acum += dt
	local t = transform.get(world, ent)

	t.position.y = math.abs(math.sin(dt_acum) * 2)

	transform.set(world, ent, t)
end
