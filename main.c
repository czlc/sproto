extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
};
#include <stdlib.h>
#include <stdio.h>

static int
_panic(lua_State *L) {
	const char * err = lua_tostring(L,-1);
	printf("%s", err);
	return 0;
}

int main(int argn, char **argv)
{
	if (argn != 2)
		return -1;

	lua_State *L = luaL_newstate();
	lua_atpanic(L, _panic);
	luaL_openlibs(L);
	if (luaL_dofile(L, argv[1]) != 0) {
		_panic(L);
	}
	system("pause");
	return 0;
}
