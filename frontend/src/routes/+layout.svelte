<script lang="ts">
	import '../app.css';

	let { children } = $props();
</script>

<svelte:head>
	<link rel="icon" href="/favicon.ico" />
	<meta name="description" content="Schützenverein Buterland-Beckerhook e.V." />
</svelte:head>

<div class="flex min-h-screen flex-col">
	<header class="bg-primary text-white">
		<nav class="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
			<a href="/" class="text-xl font-bold">Buterland-Beckerhook</a>
			<div class="hidden gap-6 md:flex">
				<a href="/aktuell" class="hover:underline">Aktuell</a>
				<a href="/termine" class="hover:underline">Termine</a>
				<a href="/thron" class="hover:underline">Thron</a>
				<a href="/verein" class="hover:underline">Verein</a>
				<a href="/kontakt" class="hover:underline">Kontakt</a>
			</div>
		</nav>
	</header>

	<main class="mx-auto w-full max-w-6xl flex-1 px-4 py-8">
		{@render children()}
	</main>

	<footer class="bg-gray-100 text-sm text-gray-600">
		<div
			class="mx-auto flex max-w-6xl flex-col items-center gap-2 px-4 py-6 md:flex-row md:justify-between"
		>
			<p>&copy; {new Date().getFullYear()} Schützenverein Buterland-Beckerhook e.V.</p>
			<div class="flex gap-4">
				<a href="/impressum" class="hover:underline">Impressum</a>
				<a href="/datenschutz" class="hover:underline">Datenschutz</a>
			</div>
		</div>
	</footer>
</div>
