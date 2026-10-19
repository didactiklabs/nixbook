package core

import "testing"

func TestOps(t *testing.T) {
	if ops, err := Ops(map[string]any{"op": "create"}, 2); err != nil || len(ops) != 1 {
		t.Fatalf("one change: %v %v", ops, err)
	}
	if _, err := Ops(map[string]any{"ops": []any{1, 2, 3}}, 2); err == nil {
		t.Fatal("over the limit: no error")
	}
	if _, err := Ops("x", 2); err == nil {
		t.Fatal("not an object: no error")
	}
}

func TestRunOps(t *testing.T) {
	signedOut := func(map[string]any) (any, error) { return nil, AuthErrorf("signed out") }
	res, authErr := RunOps([]any{map[string]any{}, "x"}, signedOut)
	if len(res) != 2 || res[0].OK || res[1].Error != "each change must be an object" || authErr == nil {
		t.Fatalf("every change refused: %+v %v", res, authErr)
	}
	calls := 0
	mixed := func(map[string]any) (any, error) {
		if calls++; calls == 1 {
			return nil, AuthErrorf("signed out")
		}
		return "done", nil
	}
	res, authErr = RunOps([]any{map[string]any{}, map[string]any{}}, mixed)
	if authErr != nil || !res[1].OK || res[1].Result != "done" {
		t.Fatalf("one change went through: %+v %v", res, authErr)
	}
	if Kind(map[string]any{"action": "delete"}) != "delete" || Kind(map[string]any{"op": "a", "action": "b"}) != "a" {
		t.Fatal("Kind")
	}
}
