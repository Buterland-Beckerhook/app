<script lang="ts">
	import type { Throne } from '$lib/types';

	let { throne }: { throne: Throne } = $props();

	let isKaiser = $derived(throne.type === 'kaiser');
	let years = $derived(throne.end != null ? `${throne.begin}–${throne.end}` : `${throne.begin}–`);
</script>

<div class="overflow-x-auto">
	<table class="w-full text-left text-sm">
		<caption class="mb-3 text-left text-lg font-semibold">
			{isKaiser ? 'Kaiserthron' : throne.type === 'stadtkaiser' ? 'Stadtkaiser' : 'Thron'}
			{years}
		</caption>
		<tbody>
			<tr class="border-b border-gray-100 dark:border-zinc-700">
				<td class="py-2 pr-4 font-medium text-gray-500 dark:text-gray-400">
					{isKaiser ? 'Kaiser' : 'König'}
				</td>
				<td class="py-2">
					{throne.king}
					{#if throne.king_title}
						als&nbsp;<span class="font-semibold">{throne.king_title}</span>
					{/if}
				</td>
			</tr>
			<tr class="border-b border-gray-100 dark:border-zinc-700">
				<td class="py-2 pr-4 font-medium text-gray-500 dark:text-gray-400">
					{isKaiser ? 'Kaiserin' : 'Königin'}
				</td>
				<td class="py-2">{throne.queen}</td>
			</tr>
			{#if throne.moh1 || throne.loh1}
				<tr class="border-b border-gray-100 dark:border-zinc-700">
					<td class="py-2 pr-4 font-medium text-gray-500 dark:text-gray-400">Ehrenpaare</td>
					<td class="py-2">
						{[throne.loh1, throne.moh1].filter(Boolean).join(' und ')}
					</td>
				</tr>
			{/if}
			{#if throne.loh2 || throne.moh2}
				<tr class="border-b border-gray-100 dark:border-zinc-700">
					<td class="py-2 pr-4 font-medium text-gray-500 dark:text-gray-400"></td>
					<td class="py-2">
						{[throne.loh2, throne.moh2].filter(Boolean).join(' und ')}
					</td>
				</tr>
			{/if}
			{#if throne.cupbearer}
				<tr class="border-b border-gray-100 dark:border-zinc-700">
					<td class="py-2 pr-4 font-medium text-gray-500 dark:text-gray-400">Mundschenk</td>
					<td class="py-2">{throne.cupbearer}</td>
				</tr>
			{/if}
			{#if throne.courtmarshal}
				<tr>
					<td class="py-2 pr-4 font-medium text-gray-500 dark:text-gray-400">Oberhofmarschall</td>
					<td class="py-2">{throne.courtmarshal}</td>
				</tr>
			{/if}
		</tbody>
	</table>
</div>
