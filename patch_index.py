import re

with open('index.html', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace Delayed Deliveries and Analysis Expiring sections with the four new ones
search_block = r"""                                    <!-- Delayed List -->
                                    <template x-if="homeOps\.delayedDeliveries\.length">
.*?
                                    </template>

                                    <!-- Analysis Expiring -->
                                    <template x-if="homeOps\.urgentAnalysis\.length">
.*?
                                    </template>

                                    <!-- Empty State -->
                                    <div x-show="!homeOps\.priorityTickets\.length && !homeOps\.delayedDeliveries\.length && !homeOps\.urgentAnalysis\.length" class="text-center py-4 text-gray-400 text-xs italic">
                                        Nenhum alerta crítico.
                                    </div>"""

replacement = """                                    <!-- Entrega Expirando -->
                                    <template x-if="homeOps.expiringDeliveries.length">
                                        <div class="mb-2">
                                            <div class="bg-amber-100 text-amber-800 text-xs px-2 py-1 rounded font-bold mb-2 flex justify-between items-center cursor-pointer hover:bg-amber-200">
                                                <span>ENTREGA EXPIRANDO (<span x-text="homeOps.expiringDeliveries.length"></span>)</span>
                                                <i class="fa-solid fa-clock text-[10px]"></i>
                                            </div>
                                            <div class="space-y-1">
                                                <template x-for="t in homeOps.expiringDeliveries.slice(0, 5)" :key="t.id">
                                                    <div @click="viewTicketDetails(t)" class="bg-amber-50 border-l-2 border-amber-500 p-2 cursor-pointer hover:bg-amber-100 transition-colors rounded-r group relative">
                                                        <div class="flex justify-between items-center text-xs mb-0.5">
                                                             <span class="font-bold text-gray-800 truncate w-2/3" x-text="t.client_name"></span>
                                                             <span class="font-mono text-amber-600 font-bold" x-text="'OS ' + t.os_number"></span>
                                                        </div>
                                                        <div class="text-[10px] text-gray-500 truncate mb-1" x-text="t.device_model"></div>
                                                        <div class="flex justify-between items-center">
                                                            <span class="text-[9px] bg-white bg-opacity-60 px-1.5 py-0.5 rounded border border-amber-200 text-amber-800 font-bold uppercase" x-text="getStatusLabel(t.status)"></span>
                                                            <span class="text-[9px] font-bold text-amber-700 uppercase"><i class="fa-regular fa-clock mr-1"></i><span x-text="t.urgency_bucket === 'today' ? 'Vence Hoje' : 'Vence Amanhã'"></span></span>
                                                        </div>
                                                    </div>
                                                </template>
                                            </div>
                                        </div>
                                    </template>

                                    <!-- Entrega Expirada -->
                                    <template x-if="homeOps.expiredDeliveries.length">
                                        <div class="mb-2">
                                            <div class="bg-red-100 text-red-800 text-xs px-2 py-1 rounded font-bold mb-2 flex justify-between items-center cursor-pointer hover:bg-red-200">
                                                <span>ENTREGA EXPIRADA (<span x-text="homeOps.expiredDeliveries.length"></span>)</span>
                                                <i class="fa-solid fa-triangle-exclamation text-[10px]"></i>
                                            </div>
                                            <div class="space-y-1">
                                                <template x-for="t in homeOps.expiredDeliveries.slice(0, 5)" :key="t.id">
                                                    <div @click="viewTicketDetails(t)" class="bg-red-50 border-l-2 border-red-500 p-2 cursor-pointer hover:bg-red-100 transition-colors rounded-r group relative">
                                                        <div class="flex justify-between items-center text-xs mb-0.5">
                                                             <span class="font-bold text-gray-800 truncate w-2/3" x-text="t.client_name"></span>
                                                             <span class="font-mono text-red-600 font-bold" x-text="'OS ' + t.os_number"></span>
                                                        </div>
                                                        <div class="text-[10px] text-gray-500 truncate mb-1" x-text="t.device_model"></div>
                                                        <div class="flex justify-between items-center">
                                                            <span class="text-[9px] bg-white bg-opacity-60 px-1.5 py-0.5 rounded border border-red-200 text-red-800 font-bold uppercase" x-text="getStatusLabel(t.status)"></span>
                                                            <span class="text-[9px] font-bold text-red-700 uppercase"><i class="fa-solid fa-clock mr-1"></i> Vencida: <span x-text="getOverdueTime(t.delivery_deadline)"></span></span>
                                                        </div>
                                                    </div>
                                                </template>
                                            </div>
                                        </div>
                                    </template>

                                    <!-- Analysis Expiring -->
                                    <template x-if="homeOps.expiringAnalysis.length">
                                        <div class="mb-2">
                                            <div class="bg-amber-100 text-amber-800 text-xs px-2 py-1 rounded font-bold mb-2 flex justify-between items-center cursor-pointer hover:bg-amber-200">
                                                <span>ANÁLISE EXPIRANDO (<span x-text="homeOps.expiringAnalysis.length"></span>)</span>
                                                <i class="fa-solid fa-stopwatch text-[10px]"></i>
                                            </div>
                                            <div class="space-y-1">
                                                <template x-for="t in homeOps.expiringAnalysis" :key="t.id">
                                                    <div @click="viewTicketDetails(t)" class="bg-amber-50 border-l-2 border-amber-500 p-2 cursor-pointer hover:bg-amber-100 transition-colors rounded-r group relative">
                                                        <div class="flex justify-between items-center text-xs mb-0.5">
                                                             <span class="font-bold text-gray-800 truncate w-2/3" x-text="t.client_name"></span>
                                                             <span class="font-mono text-amber-600 font-bold" x-text="'OS ' + t.os_number"></span>
                                                        </div>
                                                        <div class="text-[10px] text-gray-500 truncate mb-1" x-text="t.device_model"></div>
                                                        <div class="flex justify-between items-center">
                                                            <span class="text-[9px] bg-white bg-opacity-60 px-1.5 py-0.5 rounded border border-amber-200 text-amber-800 font-bold uppercase" x-text="getStatusLabel(t.status)"></span>
                                                            <span class="text-[9px] font-bold text-amber-700 uppercase"><i class="fa-regular fa-clock mr-1"></i><span x-text="t.urgency_bucket === 'today' ? 'Vence Hoje' : 'Vence Amanhã'"></span></span>
                                                        </div>
                                                    </div>
                                                </template>
                                            </div>
                                        </div>
                                    </template>

                                    <!-- Analysis Expired -->
                                    <template x-if="homeOps.expiredAnalysis.length">
                                        <div class="mb-2">
                                            <div class="bg-red-100 text-red-800 text-xs px-2 py-1 rounded font-bold mb-2 flex justify-between items-center cursor-pointer hover:bg-red-200">
                                                <span>ANÁLISE EXPIRADA (<span x-text="homeOps.expiredAnalysis.length"></span>)</span>
                                                <i class="fa-solid fa-stopwatch animate-pulse text-[10px]"></i>
                                            </div>
                                            <div class="space-y-1">
                                                <template x-for="t in homeOps.expiredAnalysis" :key="t.id">
                                                    <div @click="viewTicketDetails(t)" class="bg-red-50 border-l-2 border-red-500 p-2 cursor-pointer hover:bg-red-100 transition-colors rounded-r group relative">
                                                        <div class="flex justify-between items-center text-xs mb-0.5">
                                                             <span class="font-bold text-gray-800 truncate w-2/3" x-text="t.client_name"></span>
                                                             <span class="font-mono text-red-600 font-bold" x-text="'OS ' + t.os_number"></span>
                                                        </div>
                                                        <div class="text-[10px] text-gray-500 truncate mb-1" x-text="t.device_model"></div>
                                                        <div class="flex justify-between items-center">
                                                            <span class="text-[9px] bg-white bg-opacity-60 px-1.5 py-0.5 rounded border border-red-200 text-red-800 font-bold uppercase" x-text="getStatusLabel(t.status)"></span>
                                                            <span class="text-[9px] font-bold text-red-700 uppercase"><i class="fa-solid fa-stopwatch mr-1 animate-pulse"></i> Vencida: <span x-text="getOverdueTime(t.analysis_deadline)"></span></span>
                                                        </div>
                                                    </div>
                                                </template>
                                            </div>
                                        </div>
                                    </template>

                                    <!-- Empty State -->
                                    <div x-show="!homeOps.priorityTickets.length && !homeOps.expiringDeliveries.length && !homeOps.expiredDeliveries.length && !homeOps.expiringAnalysis.length && !homeOps.expiredAnalysis.length" class="text-center py-4 text-gray-400 text-xs italic">
                                        Nenhum alerta crítico.
                                    </div>"""

new_content = re.sub(search_block, replacement, content, flags=re.DOTALL)

with open('index.html', 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"Patched index.html")
