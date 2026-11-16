using Mono.Cecil;
using Mono.Cecil.Cil;

if (args.Length < 2)
{
    Console.Error.WriteLine("Usage: ShenzhenScalePatcher <input assembly> <output assembly> [inspect]");
    return 1;
}

var input = Path.GetFullPath(args[0]);
var output = Path.GetFullPath(args[1]);
var inspectOnly = args.Contains("inspect");
var windowedTest = args.Contains("windowed");
var scale = 2;
if (args.Length > 2 && args[2] != "inspect")
{
    int.TryParse(args[2], out scale);
}
scale = Math.Max(1, Math.Min(4, scale));

if (!File.Exists(input))
{
    Console.Error.WriteLine("Input not found: " + input);
    return 1;
}

var resolver = new DefaultAssemblyResolver();
resolver.AddSearchDirectory(Path.GetDirectoryName(input) ?? ".");
var assembly = AssemblyDefinition.ReadAssembly(input, new ReaderParameters
{
    AssemblyResolver = resolver,
    InMemory = true,
    ReadSymbols = false
});
var module = assembly.MainModule;

var gameLogic = module.GetType("GameLogic");
if (gameLogic == null)
{
    Console.Error.WriteLine("GameLogic type not found.");
    return 1;
}

MethodDefinition? createWindow = null;
Instruction? createWindowCall = null;
foreach (var method in gameLogic.Methods)
{
    if (!method.HasBody) continue;
    foreach (var instruction in method.Body.Instructions)
    {
        if (instruction.Operand is MethodReference reference && reference.Name == "SDL_CreateWindow")
        {
            createWindow = method;
            createWindowCall = instruction;
            break;
        }
    }
    if (createWindow != null) break;
}

if (createWindow == null || createWindowCall == null)
{
    Console.Error.WriteLine("SDL_CreateWindow call not found in GameLogic.");
    return 1;
}

var sdl = module.GetType("SDL2.SDL");
if (sdl == null)
{
    Console.Error.WriteLine("SDL2.SDL type not found.");
    return 1;
}

var setFullscreen = sdl.Methods.FirstOrDefault(m => m.Name == "SDL_SetWindowFullscreen");
if (setFullscreen == null)
{
    Console.Error.WriteLine("SDL_SetWindowFullscreen not found.");
    return 1;
}

var fullscreenMethods = new List<MethodDefinition>();
foreach (var type in module.Types)
{
    foreach (var method in type.Methods)
    {
        if (!method.HasBody) continue;
        if (method.Body.Instructions.Any(i => i.Operand is MethodReference r && r.Name == "SDL_SetWindowFullscreen"))
        {
            fullscreenMethods.Add(method);
        }
    }
}

Console.WriteLine("CreateWindow method: " + createWindow.FullName);
Console.WriteLine("CreateWindow parameters: " + string.Join(", ", createWindow.Parameters.Select(p => p.ParameterType.FullName + " " + p.Name)));
Console.WriteLine("Fullscreen methods: " + string.Join("; ", fullscreenMethods.Select(m => m.FullName)));

if (inspectOnly)
{
    var index = 0;
    foreach (var instruction in createWindow.Body.Instructions.Take(60))
    {
        Console.WriteLine(index + ": " + instruction);
        index++;
    }
    foreach (var type in module.Types)
    {
        foreach (var method in type.Methods)
        {
            if (method.Parameters.Count == 0 && method.ReturnType.Name == "Index2")
            {
                Console.WriteLine("Index2 method: " + method.FullName);
            }
            if (method.DeclaringType.Name == "Renderer" && method.Parameters.Count == 3 &&
                method.Parameters[1].ParameterType.MetadataType == MetadataType.Int32 &&
                method.Parameters[2].ParameterType.MetadataType == MetadataType.Int32)
            {
                Console.WriteLine("Renderer int,int method: " + method.FullName);
            }
        }
    }
    var scaleType = module.GetType("ShenzhenScaleMod");
    if (scaleType != null)
    {
        var scaleMethod = scaleType.Methods.FirstOrDefault(m => m.Name == "GetScale");
        if (scaleMethod != null)
        {
            Console.WriteLine("GetScale: " + scaleMethod.FullName + " returns " + scaleMethod.ReturnType.MetadataType);
            var scaleIndex = 0;
            foreach (var instruction in scaleMethod.Body.Instructions)
            {
                Console.WriteLine("S" + scaleIndex + ": " + instruction);
                scaleIndex++;
            }
        }
    }
    return 0;
}

var setFullscreenRef = module.ImportReference(setFullscreen);
InsertScaleAtStart(createWindow, scale);

if (!windowedTest)
{
    InsertForceFullscreen(createWindow, createWindowCall, setFullscreenRef);
    foreach (var method in fullscreenMethods)
    {
        var booleanParameter = method.Parameters.FirstOrDefault(p => p.ParameterType.MetadataType == MetadataType.Boolean);
        if (booleanParameter != null)
        {
            ForceBooleanParameter(method, booleanParameter);
        }
    }
}
PatchRendererResize(module, scale);
PatchRendererInit(module, scale);

var targetDirectory = Path.GetDirectoryName(output);
if (!string.IsNullOrEmpty(targetDirectory))
{
    Directory.CreateDirectory(targetDirectory);
}
assembly.Write(output);
Console.WriteLine("Patched assembly written: " + output);
return 0;

static void PatchRendererInit(ModuleDefinition module, int scale)
{
    var renderer = module.GetType("Renderer");
    if (renderer == null) return;
    var method = renderer.Methods.FirstOrDefault(m => m.HasBody && m.Parameters.Count == 3 &&
        m.Parameters[0].ParameterType.MetadataType == MetadataType.IntPtr &&
        m.Parameters[1].ParameterType.MetadataType == MetadataType.Int32 &&
        m.Parameters[2].ParameterType.MetadataType == MetadataType.Int32);
    if (method == null)
    {
        Console.WriteLine("Renderer init method not found.");
        return;
    }
    var instructions = new List<Instruction>
    {
        Instruction.Create(OpCodes.Ldarg, method.Parameters[1]),
        Instruction.Create(OpCodes.Ldc_I4, scale),
        Instruction.Create(OpCodes.Div),
        Instruction.Create(OpCodes.Starg, method.Parameters[1]),
        Instruction.Create(OpCodes.Ldarg, method.Parameters[2]),
        Instruction.Create(OpCodes.Ldc_I4, scale),
        Instruction.Create(OpCodes.Div),
        Instruction.Create(OpCodes.Starg, method.Parameters[2])
    };
    var first = method.Body.Instructions[0];
    var il = method.Body.GetILProcessor();
    for (var i = 0; i < instructions.Count; i++)
    {
        il.InsertBefore(first, instructions[i]);
    }
    Console.WriteLine("Patched renderer init: " + method.FullName);
}

static void PatchResolutionGetter(ModuleDefinition module, int scale)
{
    var getter = module.Types
        .SelectMany(t => t.Methods)
        .FirstOrDefault(m => m.HasBody && m.Parameters.Count == 0 && m.ReturnType.Name == "Index2" &&
            m.DeclaringType.Fields.Any(f => f.FieldType.Name.Contains("Y9Fn")) &&
            m.Body.Instructions.Any(i => i.OpCode == OpCodes.Newobj && i.Operand is MethodReference r && r.DeclaringType.Name == "Index2"));
    if (getter == null)
    {
        Console.WriteLine("Resolution getter not found.");
        return;
    }

    var newObj = getter.Body.Instructions.First(i => i.OpCode == OpCodes.Newobj && i.Operand is MethodReference r && r.DeclaringType.Name == "Index2");
    var temp = new VariableDefinition(module.TypeSystem.Int32);
    getter.Body.Variables.Add(temp);
    var instructions = new List<Instruction>
    {
        Instruction.Create(OpCodes.Stloc, temp),
        Instruction.Create(OpCodes.Ldc_I4, scale),
        Instruction.Create(OpCodes.Div),
        Instruction.Create(OpCodes.Ldloc, temp),
        Instruction.Create(OpCodes.Ldc_I4, scale),
        Instruction.Create(OpCodes.Div)
    };
    var il = getter.Body.GetILProcessor();
    for (var i = 0; i < instructions.Count; i++)
    {
        il.InsertBefore(newObj, instructions[i]);
    }
    Console.WriteLine("Patched resolution getter: " + getter.FullName);
}

static void PatchRendererResize(ModuleDefinition module, int scale)
{
    var renderer = module.GetType("Renderer");
    if (renderer == null) return;
    var method = renderer.Methods.FirstOrDefault(m => m.HasBody && m.ReturnType.MetadataType == MetadataType.Void &&
        m.Parameters.Count == 3 && m.Parameters[1].ParameterType.MetadataType == MetadataType.Int32 &&
        m.Parameters[2].ParameterType.MetadataType == MetadataType.Int32);
    if (method == null)
    {
        Console.WriteLine("Renderer resize method not found.");
        return;
    }

    var instructions = new List<Instruction>
    {
        Instruction.Create(OpCodes.Ldarg, method.Parameters[1]),
        Instruction.Create(OpCodes.Ldc_I4, scale),
        Instruction.Create(OpCodes.Div),
        Instruction.Create(OpCodes.Starg, method.Parameters[1]),
        Instruction.Create(OpCodes.Ldarg, method.Parameters[2]),
        Instruction.Create(OpCodes.Ldc_I4, scale),
        Instruction.Create(OpCodes.Div),
        Instruction.Create(OpCodes.Starg, method.Parameters[2])
    };
    var first = method.Body.Instructions[0];
    var il = method.Body.GetILProcessor();
    for (var i = 0; i < instructions.Count; i++)
    {
        il.InsertBefore(first, instructions[i]);
    }
    Console.WriteLine("Patched renderer resize: " + method.FullName);
}

static void InsertScaleAtStart(MethodDefinition method, int scale)
{
    if (method.Parameters.Count < 3)
    {
        throw new InvalidOperationException("Unexpected CreateWindow parameter count.");
    }

    var instructions = new List<Instruction>
    {
        Instruction.Create(OpCodes.Ldarg, method.Parameters[1]),
        Instruction.Create(OpCodes.Ldc_I4, scale),
        Instruction.Create(OpCodes.Div),
        Instruction.Create(OpCodes.Starg, method.Parameters[1]),
        Instruction.Create(OpCodes.Ldarg, method.Parameters[2]),
        Instruction.Create(OpCodes.Ldc_I4, scale),
        Instruction.Create(OpCodes.Div),
        Instruction.Create(OpCodes.Starg, method.Parameters[2])
    };

    var first = method.Body.Instructions[0];
    var il = method.Body.GetILProcessor();
    for (var i = 0; i < instructions.Count; i++)
    {
        il.InsertBefore(first, instructions[i]);
    }
}

static void InsertForceFullscreen(MethodDefinition method, Instruction createWindowCall, MethodReference setFullscreen)
{
    var next = createWindowCall.Next ?? throw new InvalidOperationException("CreateWindow call has no next instruction.");
    var instructions = new List<Instruction>
    {
        Instruction.Create(OpCodes.Dup),
        Instruction.Create(OpCodes.Ldc_I4, 4097),
        Instruction.Create(OpCodes.Call, setFullscreen),
        Instruction.Create(OpCodes.Pop)
    };
    var il = method.Body.GetILProcessor();
    for (var i = 0; i < instructions.Count; i++)
    {
        il.InsertBefore(next, instructions[i]);
    }
}

static void ForceBooleanParameter(MethodDefinition method, ParameterDefinition parameter)
{
    var first = method.Body.Instructions[0];
    var il = method.Body.GetILProcessor();
    il.InsertBefore(first, Instruction.Create(OpCodes.Ldc_I4_1));
    il.InsertBefore(first, Instruction.Create(OpCodes.Starg, parameter));
}
