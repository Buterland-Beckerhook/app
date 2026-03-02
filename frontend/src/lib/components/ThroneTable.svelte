<script lang="ts">
	import type { Throne } from '$lib/types';

	let { throne }: { throne: Throne } = $props();

	let isKaiser = $derived(throne.type === 'kaiserthron');
</script>

<div class="overflow-x-auto">
	<table class="w-full text-left text-sm">
		<caption class="mb-3 text-left text-lg font-semibold">
			{isKaiser ? 'Kaiserthron' : 'Thron'}
			{throne.years}
		</caption>
		<tbody>
			<tr class="border-b border-gray-100 dark:border-gray-700">
				<td class="py-2 pr-4 font-medium text-gray-500 dark:text-gray-400">
					{isKaiser ? 'Kaiser' : 'König'}
				</td>
				<td class="py-2">
					{#if throne.king_title}
						<span class="font-semibold">{throne.king_title}</span> &mdash;
					{/if}
					{throne.king}
				</td>
			</tr>
			<tr class="border-b border-gray-100 dark:border-gray-700">
				<td class="py-2 pr-4 font-medium text-gray-500 dark:text-gray-400">
					{isKaiser ? 'Kaiserin' : 'Königin'}
				</td>
				<td class="py-2">{throne.queen}</td>
			</tr>
			{#if throne.moh1 || throne.moh2}
				<tr class="border-b border-gray-100 dark:border-gray-700">
					<td class="py-2 pr-4 font-medium text-gray-500 dark:text-gray-400">Ehrendamen</td>
					<td class="py-2">
						{[throne.moh1, throne.moh2].filter(Boolean).join(', ')}
					</td>
				</tr>
			{/if}
			{#if throne.loh1 || throne.loh2}
				<tr class="border-b border-gray-100 dark:border-gray-700">
					<td class="py-2 pr-4 font-medium text-gray-500 dark:text-gray-400">Ehrenherren</td>
					<td class="py-2">
						{[throne.loh1, throne.loh2].filter(Boolean).join(', ')}
					</td>
				</tr>
			{/if}
			{#if throne.cupbearer}
				<tr class="border-b border-gray-100 dark:border-gray-700">
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
