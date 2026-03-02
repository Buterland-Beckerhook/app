<script lang="ts">
	import type { Event } from '$lib/types';
	import DateFormat from './DateFormat.svelte';

	let { event }: { event: Event } = $props();

	let isCanceled = $derived(event.status === 'canceled');
	let locationName = $derived(
		typeof event.location === 'object' && event.location ? event.location.name : null
	);
</script>

<article
	class="rounded-lg border border-gray-200 p-4 transition-shadow hover:shadow-md dark:border-zinc-700"
	class:opacity-60={isCanceled}
>
	<a href="/termine/{event.slug}" class="block">
		<div class="flex flex-col gap-2">
			<div class="flex items-start justify-between gap-2">
				<time datetime={event.start} class="text-sm font-medium text-primary">
					<DateFormat date={event.start} />
				</time>
				{#if isCanceled}
					<span
						class="rounded bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700 dark:bg-red-900/30 dark:text-red-300"
					>
						Abgesagt
					</span>
				{/if}
			</div>
			<h3 class="text-lg font-semibold" class:line-through={isCanceled}>
				{event.title}
			</h3>
			{#if locationName}
				<p class="text-sm text-gray-500 dark:text-gray-400">{locationName}</p>
			{/if}
			{#if isCanceled && event.cancel_reason}
				<p class="text-sm text-red-600 dark:text-red-400">{event.cancel_reason}</p>
			{/if}
		</div>
	</a>
</article>
