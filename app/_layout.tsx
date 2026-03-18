import { Stack } from "expo-router";

export default function RootLayout() {
  return (
    <Stack>
      <Stack.Screen name="index" options={{ title: "Object Capture PoC" }} />
      <Stack.Screen name="viewer" options={{ title: "3D Viewer" }} />
    </Stack>
  );
}
