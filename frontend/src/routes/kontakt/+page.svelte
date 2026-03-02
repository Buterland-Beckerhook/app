<svelte:head>
	<title>Kontakt &mdash; Schützenverein Buterland-Beckerhook</title>
	<meta
		name="description"
		content="Kontaktieren Sie den Schützenverein Buterland-Beckerhook e.V."
	/>
</svelte:head>

<h1 class="mb-8 text-3xl font-bold">Kontakt</h1>

<div class="mx-auto max-w-2xl">
	<p class="mb-6 text-gray-600">
		Sie haben Fragen oder Anregungen? Nehmen Sie gerne Kontakt mit uns auf.
	</p>

	<form method="POST" class="space-y-4">
		<div>
			<label for="name" class="mb-1 block text-sm font-medium">Name</label>
			<input
				type="text"
				id="name"
				name="name"
				required
				class="w-full rounded-lg border border-gray-300 px-4 py-2 focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
			/>
		</div>

		<div>
			<label for="email" class="mb-1 block text-sm font-medium">E-Mail</label>
			<input
				type="email"
				id="email"
				name="email"
				required
				class="w-full rounded-lg border border-gray-300 px-4 py-2 focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
			/>
		</div>

		<div>
			<label for="message" class="mb-1 block text-sm font-medium">Nachricht</label>
			<textarea
				id="message"
				name="message"
				rows="5"
				required
				class="w-full rounded-lg border border-gray-300 px-4 py-2 focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
			></textarea>
		</div>

		<div class="flex items-start gap-2">
			<input type="checkbox" id="privacy" name="privacy" required class="mt-1" />
			<label for="privacy" class="text-sm text-gray-600">
				Ich habe die <a href="/datenschutz" class="text-primary hover:underline"
					>Datenschutzerklärung</a
				> gelesen und stimme der Verarbeitung meiner Daten zu.
			</label>
		</div>

		<button
			type="submit"
			class="rounded-lg bg-primary px-6 py-2 font-medium text-white hover:bg-primary-dark"
		>
			Nachricht senden
		</button>
	</form>
</div>
