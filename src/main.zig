const ray = @cImport({
    @cInclude("raylib.h");
});

pub fn main() void {
    ray.InitWindow(800, 450, "raylib [core] example - basic window");

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        ray.ClearBackground(ray.RAYWHITE);
        ray.DrawText("Congrats! You created your first window!", 190, 200, 20, ray.LIGHTGRAY);
        ray.EndDrawing();
    }
}
